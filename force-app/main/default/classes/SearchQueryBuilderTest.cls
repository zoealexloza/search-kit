@IsTest
private class SearchQueryBuilderTest {
  private static SearchConfig.ObjectConfig accountConfig() {
    SearchConfig.ObjectConfig objectConfig = new SearchConfig.ObjectConfig();
    objectConfig.developerName = 'Accounts';
    objectConfig.objectApiName = 'Account';
    objectConfig.titleField = 'Name';
    objectConfig.detailFields = new List<String>{ 'Industry' };
    return objectConfig;
  }

  private static SearchConfig.RuleConfig ruleConfig(
    String field,
    String operator,
    String value
  ) {
    SearchConfig.RuleConfig rule = new SearchConfig.RuleConfig();
    rule.developerName = 'Rule';
    rule.fieldApiName = field;
    rule.operator = operator;
    rule.value = value;
    rule.points = 5;
    return rule;
  }

  private static SearchConfig.FacetConfig facetConfig(String field) {
    SearchConfig.FacetConfig facet = new SearchConfig.FacetConfig();
    facet.developerName = 'Facet';
    facet.fieldApiName = field;
    return facet;
  }

  // ---- sanitizeTerm ----

  @IsTest
  static void sanitizeTermHandlesBlankInput() {
    Assert.areEqual('', SearchQueryBuilder.sanitizeTerm(null));
    Assert.areEqual('', SearchQueryBuilder.sanitizeTerm(''));
    Assert.areEqual('', SearchQueryBuilder.sanitizeTerm('   \t\n  '));
  }

  @IsTest
  static void sanitizeTermCollapsesWhitespace() {
    Assert.areEqual(
      'reset my password',
      SearchQueryBuilder.sanitizeTerm('  reset   my\tpassword  ')
    );
  }

  @IsTest
  static void sanitizeTermStripsEverySoslReservedCharacter() {
    String reserved = '?&|!{}[]()^~*:\\"\'+-';
    for (Integer i = 0; i < reserved.length(); i++) {
      String ch = reserved.substring(i, i + 1);
      Assert.areEqual(
        'ab cd',
        SearchQueryBuilder.sanitizeTerm('ab' + ch + 'cd'),
        'Character not stripped: ' + ch
      );
    }
    Assert.areEqual('', SearchQueryBuilder.sanitizeTerm(reserved));
  }

  @IsTest
  static void sanitizeTermStripsQuotesAndBackslashesUsedForInjection() {
    Assert.areEqual('O Brien', SearchQueryBuilder.sanitizeTerm('O\'Brien'));
    Assert.areEqual('test', SearchQueryBuilder.sanitizeTerm('test\\'));
    Assert.areEqual(
      'x RETURNING User Id',
      SearchQueryBuilder.sanitizeTerm('x\' RETURNING User(Id)')
    );
    Assert.areEqual('a b', SearchQueryBuilder.sanitizeTerm('a\\\' b'));
  }

  @IsTest
  static void sanitizeTermStripsControlCharactersAndKeepsUnicode() {
    String withControl =
      'line' +
      String.fromCharArray(new List<Integer>{ 0, 7, 27 }) +
      'break';
    Assert.areEqual('line break', SearchQueryBuilder.sanitizeTerm(withControl));
    Assert.areEqual(
      'café Zürich 東京',
      SearchQueryBuilder.sanitizeTerm('café Zürich 東京')
    );
  }

  @IsTest
  static void sanitizeTermLimitsVeryLongInput() {
    String longTerm = 'word '.repeat(20000);
    String term = SearchQueryBuilder.sanitizeTerm(longTerm);
    Assert.isTrue(
      term.length() <= SearchQueryBuilder.MAX_TERM_LENGTH,
      'Term is capped'
    );
    Assert.isFalse(term.endsWith(' '), 'No trailing space after cutting');
    Assert.areEqual(
      SearchQueryBuilder.MAX_TERM_LENGTH,
      SearchQueryBuilder.sanitizeTerm('x'.repeat(5000)).length()
    );
  }

  // ---- literals ----

  @IsTest
  static void quoteEscapesBackslashesThenQuotes() {
    Assert.areEqual('\'plain\'', SearchQueryBuilder.quote('plain'));
    Assert.areEqual('\'O\\\'Brien\'', SearchQueryBuilder.quote('O\'Brien'));
    Assert.areEqual('\'a\\\\b\'', SearchQueryBuilder.quote('a\\b'));
    // a\' becomes a\\\' : escaped backslash, then escaped quote. The literal cannot be closed early.
    Assert.areEqual(
      '\'a\\\\\\\' OR Name != \\\'\'',
      SearchQueryBuilder.quote('a\\\' OR Name != \'')
    );
  }

  @IsTest
  static void quotedLiteralsMatchExactValuesInARealQuery() {
    String tricky = 'Tricky \\ name \' with quote';
    insert new List<Account>{
      new Account(Name = tricky),
      new Account(Name = 'Plain')
    };

    // Deliberately dynamic SOQL with literals: this is the SOSL literal path, proven on SOQL.
    List<Account> exact = Database.query(
      'SELECT Id FROM Account WHERE Name = ' + SearchQueryBuilder.quote(tricky),
      AccessLevel.USER_MODE
    );
    List<Account> injected = Database.query(
      'SELECT Id FROM Account WHERE Name = ' +
      SearchQueryBuilder.quote('x\' OR Name != \''),
      AccessLevel.USER_MODE
    );
    List<Account> injectedWithBackslash = Database.query(
      'SELECT Id FROM Account WHERE Name = ' +
      SearchQueryBuilder.quote('x\\\' OR Name != \''),
      AccessLevel.USER_MODE
    );

    Assert.areEqual(
      1,
      exact.size(),
      'Value with backslash and quote matches itself'
    );
    Assert.areEqual(
      0,
      injected.size(),
      'Quote injection stays inside the literal'
    );
    Assert.areEqual(
      0,
      injectedWithBackslash.size(),
      'Backslash-quote injection stays inside the literal'
    );
  }

  @IsTest
  static void toLiteralFormatsEachType() {
    Assert.areEqual('true', SearchQueryBuilder.toLiteral(true));
    Assert.areEqual('12.50', SearchQueryBuilder.toLiteral(12.50));
    Assert.areEqual(
      '10000000000',
      SearchQueryBuilder.toLiteral(Decimal.valueOf('1E+10'))
    );
    Assert.areEqual(
      '2026-03-04',
      SearchQueryBuilder.toLiteral(Date.newInstance(2026, 3, 4))
    );
    Assert.areEqual(
      '2026-03-04T05:06:07Z',
      SearchQueryBuilder.toLiteral(Datetime.newInstanceGmt(2026, 3, 4, 5, 6, 7))
    );
    Assert.areEqual('\'x\'', SearchQueryBuilder.toLiteral('x'));
  }

  @IsTest
  static void toLiteralRejectsUnsupportedTypes() {
    try {
      SearchQueryBuilder.toLiteral(new Account());
      Assert.fail('Expected IllegalArgumentException');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('Unsupported'));
    }
  }

  // ---- conditions ----

  @IsTest
  static void fromRuleMapsEveryFilterOperator() {
    SchemaValidator validator = new SchemaValidator();
    Schema.DescribeSObjectResult accountDescribe = Account.SObjectType.getDescribe(
      SObjectDescribeOptions.DEFERRED
    );

    String industry = SearchTestFactory.picklistValues(Account.Industry, 1)[0];

    Map<String, SearchTarget.FieldRule> rules = new Map<String, SearchTarget.FieldRule>{
      'Industry = :p0' => validator.validateRule(
        accountDescribe,
        ruleConfig('Industry', 'equals', industry),
        true
      ),
      'Industry != :p0' => validator.validateRule(
        accountDescribe,
        ruleConfig('Industry', 'not_equals', industry),
        true
      ),
      'NumberOfEmployees > :p0' => validator.validateRule(
        accountDescribe,
        ruleConfig('NumberOfEmployees', 'greater_than', '10'),
        true
      ),
      'NumberOfEmployees < :p0' => validator.validateRule(
        accountDescribe,
        ruleConfig('NumberOfEmployees', 'less_than', '10'),
        true
      ),
      'IsEscalated = :p0' => validator.validateRule(
        Case.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED),
        ruleConfig('IsEscalated', 'is_true', null),
        true
      )
    };
    for (String expected : rules.keySet()) {
      Map<String, Object> binds = new Map<String, Object>();
      String whereClause = SearchQueryBuilder.buildWhere(
        new List<SearchQueryBuilder.Condition>{
          SearchQueryBuilder.fromRule(rules.get(expected))
        },
        binds
      );
      Assert.areEqual(' WHERE ' + expected, whereClause);
      Assert.areEqual(1, binds.size());
    }
  }

  @IsTest
  static void fromRuleBuildsIncludesForMultiSelectRules() {
    SearchTarget.FieldRule rule = new SearchTarget.FieldRule();
    rule.field = Account.Industry.getDescribe();
    rule.operator = SchemaValidator.OP_INCLUDES;
    rule.value = 'A';
    SearchQueryBuilder.Condition condition = SearchQueryBuilder.fromRule(rule);
    Assert.areEqual(
      ' WHERE Industry INCLUDES (\'A\')',
      SearchQueryBuilder.buildWhere(
        new List<SearchQueryBuilder.Condition>{ condition },
        null
      )
    );
  }

  @IsTest
  static void fromRuleRejectsBoostOnlyOperator() {
    SearchTarget.FieldRule rule = new SearchTarget.FieldRule();
    rule.field = Account.Name.getDescribe();
    rule.operator = SchemaValidator.OP_CONTAINS;
    rule.value = 'x';
    try {
      SearchQueryBuilder.fromRule(rule);
      Assert.fail('Expected IllegalArgumentException');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('contains'));
    }
  }

  @IsTest
  static void fromFacetUsesInForPicklistsAndEqualsForCheckboxes() {
    SearchTarget.Facet picklist = new SearchTarget.Facet();
    picklist.field = Account.Industry.getDescribe();
    SearchTarget.Facet checkbox = new SearchTarget.Facet();
    checkbox.field = Case.IsEscalated.getDescribe();

    SearchQueryBuilder.Condition inCondition = SearchQueryBuilder.fromFacet(
      picklist,
      new List<Object>{ 'A', 'B' }
    );
    SearchQueryBuilder.Condition boolCondition = SearchQueryBuilder.fromFacet(
      checkbox,
      new List<Object>{ true }
    );

    Assert.areEqual(
      ' WHERE Industry IN (\'A\', \'B\') AND IsEscalated = true',
      SearchQueryBuilder.buildWhere(
        new List<SearchQueryBuilder.Condition>{ inCondition, boolCondition },
        null
      )
    );
    Assert.isNull(
      SearchQueryBuilder.fromFacet(checkbox, new List<Object>{ true, false }),
      'Both checkbox values selected restricts nothing'
    );
  }

  @IsTest
  static void buildWhereIsEmptyWithoutConditions() {
    Assert.areEqual(
      '',
      SearchQueryBuilder.buildWhere(
        new List<SearchQueryBuilder.Condition>(),
        null
      )
    );
  }

  // ---- full queries ----

  @IsTest
  static void buildSoslCombinesTermFieldsFiltersFacetsAndLimit() {
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      2
    );
    SearchConfig.ObjectConfig objectConfig = accountConfig();
    objectConfig.filterRules.add(
      ruleConfig('NumberOfEmployees', 'greater_than', '5')
    );
    objectConfig.boostRules.add(
      ruleConfig(
        'Rating',
        'equals',
        SearchTestFactory.picklistValues(Account.Rating, 1)[0]
      )
    );
    objectConfig.facets.add(facetConfig('Industry'));
    SearchConfig.ObjectConfig contactConfig = new SearchConfig.ObjectConfig();
    contactConfig.developerName = 'Contacts';
    contactConfig.objectApiName = 'Contact';
    contactConfig.titleField = 'LastName';
    SchemaValidator validator = new SchemaValidator();
    List<SearchTarget> targets = new List<SearchTarget>{
      validator.validate(objectConfig),
      validator.validate(contactConfig)
    };
    SearchTarget.Facet industryFacet = targets[0].facets[0];
    Map<String, List<SearchQueryBuilder.Condition>> facetConditions = new Map<String, List<SearchQueryBuilder.Condition>>{
      'account' => new List<SearchQueryBuilder.Condition>{
        SearchQueryBuilder.fromFacet(
          industryFacet,
          new List<Object>{ industries[0], industries[1] }
        )
      }
    };

    String sosl = SearchQueryBuilder.buildSosl(
      'reset password',
      targets,
      facetConditions,
      11
    );

    Assert.areEqual(
      'FIND \'reset password\' IN ALL FIELDS RETURNING ' +
        'Account(Id, Name, Industry, Rating WHERE NumberOfEmployees > 5 AND Industry IN (\'' +
        industries[0] +
        '\', \'' +
        industries[1] +
        '\') LIMIT 11), ' +
        'Contact(Id, LastName LIMIT 11)',
      sosl
    );
  }

  @IsTest
  static void buildSoqlBindsEveryValueAndSortsByTitle() {
    String industry = SearchTestFactory.picklistValues(Account.Industry, 1)[0];
    SearchConfig.ObjectConfig objectConfig = accountConfig();
    objectConfig.filterRules.add(
      ruleConfig('NumberOfEmployees', 'greater_than', '5')
    );
    objectConfig.facets.add(facetConfig('Industry'));
    SearchTarget target = new SchemaValidator().validate(objectConfig);
    Map<String, List<SearchQueryBuilder.Condition>> facetConditions = new Map<String, List<SearchQueryBuilder.Condition>>{
      'account' => new List<SearchQueryBuilder.Condition>{
        SearchQueryBuilder.fromFacet(
          target.facets[0],
          new List<Object>{ industry }
        )
      }
    };

    SearchQueryBuilder.QuerySpec spec = SearchQueryBuilder.buildSoql(
      target,
      facetConditions,
      6
    );

    Assert.areEqual(
      'SELECT Id, Name, Industry FROM Account WHERE NumberOfEmployees > :p0 AND Industry IN (:p1) ORDER BY Name ASC NULLS LAST, Id ASC LIMIT 6',
      spec.query
    );
    Assert.areEqual(
      5,
      spec.binds.get('p0'),
      'Integer field gets an Integer bind'
    );
    Assert.areEqual(industry, spec.binds.get('p1'));
    // The query must actually run.
    Assert.isNotNull(
      Database.queryWithBinds(spec.query, spec.binds, AccessLevel.USER_MODE)
    );
  }

  // ---- M8 operators ----

  private static SearchTarget.FieldRule validFilter(
    Schema.SObjectType type,
    String field,
    String operator,
    String value
  ) {
    SearchTarget.FieldRule rule = new SchemaValidator()
      .validateRule(
        type.getDescribe(SObjectDescribeOptions.DEFERRED),
        ruleConfig(field, operator, value),
        true
      );
    Assert.isNotNull(
      rule,
      'Test rule should be valid: ' + field + ' ' + operator
    );
    return rule;
  }

  private static String soqlWhere(SearchTarget.FieldRule rule) {
    return SearchQueryBuilder.buildWhere(
      new List<SearchQueryBuilder.Condition>{
        SearchQueryBuilder.fromRule(rule)
      },
      new Map<String, Object>()
    );
  }

  private static String soslWhere(SearchTarget.FieldRule rule) {
    return SearchQueryBuilder.buildWhere(
      new List<SearchQueryBuilder.Condition>{
        SearchQueryBuilder.fromRule(rule)
      },
      null
    );
  }

  @IsTest
  static void fromRuleMapsNewOperators() {
    RelativeDateParser.todayOverride = Date.newInstance(2026, 3, 1);
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      2
    );

    SearchTarget.FieldRule blank = validFilter(
      Account.SObjectType,
      'Industry',
      'is_blank',
      null
    );
    Assert.areEqual(' WHERE Industry = null', soqlWhere(blank));
    Assert.areEqual(' WHERE Industry = null', soslWhere(blank));

    SearchTarget.FieldRule notBlank = validFilter(
      Account.SObjectType,
      'Industry',
      'is_not_blank',
      null
    );
    Assert.areEqual(' WHERE Industry != null', soqlWhere(notBlank));
    Assert.areEqual(' WHERE Industry != null', soslWhere(notBlank));

    SearchTarget.FieldRule picklistIn = validFilter(
      Account.SObjectType,
      'Industry',
      'in',
      industries[0] + ';' + industries[1]
    );
    Assert.areEqual(' WHERE Industry IN (:p0, :p1)', soqlWhere(picklistIn));
    Assert.areEqual(
      ' WHERE Industry IN (\'' +
        industries[0] +
        '\', \'' +
        industries[1] +
        '\')',
      soslWhere(picklistIn)
    );

    SearchTarget.FieldRule numberIn = validFilter(
      Account.SObjectType,
      'NumberOfEmployees',
      'in',
      '10;20'
    );
    Assert.areEqual(
      ' WHERE NumberOfEmployees IN (10, 20)',
      soslWhere(numberIn)
    );

    SearchTarget.FieldRule textIn = validFilter(
      Account.SObjectType,
      'Name',
      'in',
      'Acme;x\' OR Name != \''
    );
    Assert.areEqual(
      ' WHERE Name IN (\'Acme\', \'x\\\' OR Name != \\\'\')',
      soslWhere(textIn),
      'Each text value is escaped inside its own literal'
    );

    SearchTarget.FieldRule recentDate = validFilter(
      Contact.SObjectType,
      'Birthdate',
      'greater_than',
      'LAST_N_DAYS:30'
    );
    Assert.areEqual(' WHERE Birthdate > :p0', soqlWhere(recentDate));
    Assert.areEqual(' WHERE Birthdate > 2026-01-30', soslWhere(recentDate));

    SearchTarget.FieldRule recentDatetime = validFilter(
      Task.SObjectType,
      'ReminderDateTime',
      'greater_than',
      'LAST_N_DAYS:30'
    );
    Assert.areEqual(
      ' WHERE ReminderDateTime >= :p0',
      soqlWhere(recentDatetime)
    );
    Assert.areEqual(
      ' WHERE ReminderDateTime >= ' +
      RelativeDateParser.startOfDay(Date.newInstance(2026, 1, 31))
        .formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
      soslWhere(recentDatetime)
    );
  }

  @IsTest
  static void fromRuleBuildsIncludesForMultiSelectIn() {
    Schema.DescribeFieldResult channel = SearchTestFactory.multiSelectField();
    if (channel == null) {
      return; // QuickText is not available in this org.
    }
    SearchTarget.FieldRule rule = new SearchTarget.FieldRule();
    rule.field = channel;
    rule.operator = SchemaValidator.OP_IN;
    rule.value = new List<Object>{ 'A', 'B' };
    Assert.areEqual(' WHERE Channel INCLUDES (\'A\', \'B\')', soslWhere(rule));
  }

  /**
   * Runs every new operator as a real filter (SOQL with binds) and checks that the boost engine
   * agrees with the query on every record, so a filter and a boost with the same rule always
   * select the same records.
   */
  @IsTest
  static void newOperatorsRunInSoqlAndAgreeWithBoostMatching() {
    Date today = Date.today();
    RelativeDateParser.todayOverride = today;
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      3
    );
    insert new List<Account>{
      new Account(
        Name = 'Alpha',
        NumberOfEmployees = 10,
        Industry = industries[0]
      ),
      new Account(Name = 'Beta', Industry = industries[1]),
      new Account(Name = 'Gamma', NumberOfEmployees = 20),
      new Account(
        Name = 'Delta',
        NumberOfEmployees = 30,
        Industry = industries[2]
      )
    };
    insert new List<Contact>{
      new Contact(LastName = 'Recent', Birthdate = today.addDays(-29)),
      new Contact(LastName = 'Boundary', Birthdate = today.addDays(-30)),
      new Contact(LastName = 'Old', Birthdate = today.addDays(-31)),
      new Contact(LastName = 'Upcoming', Birthdate = today.addDays(3)),
      new Contact(LastName = 'None')
    };
    Datetime startOfCutoffDay = RelativeDateParser.startOfDay(
      today.addDays(-29)
    );
    insert new List<Task>{
      new Task(Subject = 'At midnight', ReminderDateTime = startOfCutoffDay),
      new Task(
        Subject = 'Second before',
        ReminderDateTime = startOfCutoffDay.addSeconds(-1)
      ),
      new Task(Subject = 'Today', ReminderDateTime = Datetime.now())
    };

    List<LiveCase> cases = new List<LiveCase>{
      new LiveCase(
        Account.SObjectType,
        'Name',
        'NumberOfEmployees',
        'is_blank',
        null,
        new List<String>{ 'Beta' }
      ),
      new LiveCase(
        Account.SObjectType,
        'Name',
        'Industry',
        'is_not_blank',
        null,
        new List<String>{ 'Alpha', 'Beta', 'Delta' }
      ),
      new LiveCase(
        Account.SObjectType,
        'Name',
        'NumberOfEmployees',
        'in',
        '10;30',
        new List<String>{ 'Alpha', 'Delta' }
      ),
      new LiveCase(
        Account.SObjectType,
        'Name',
        'Industry',
        'in',
        industries[0] + ';' + industries[1],
        new List<String>{ 'Alpha', 'Beta' }
      ),
      new LiveCase(
        Account.SObjectType,
        'Name',
        'Name',
        'in',
        'alpha;GAMMA;Nobody',
        new List<String>{ 'Alpha', 'Gamma' }
      ),
      new LiveCase(
        Contact.SObjectType,
        'LastName',
        'Birthdate',
        'greater_than',
        'LAST_N_DAYS:30',
        new List<String>{ 'Recent', 'Upcoming' }
      ),
      new LiveCase(
        Contact.SObjectType,
        'LastName',
        'Birthdate',
        'less_than',
        'TODAY',
        new List<String>{ 'Boundary', 'Old', 'Recent' }
      ),
      new LiveCase(
        Contact.SObjectType,
        'LastName',
        'Birthdate',
        'equals',
        'NEXT_N_DAYS:3',
        new List<String>{ 'Upcoming' }
      ),
      new LiveCase(
        Task.SObjectType,
        'Subject',
        'ReminderDateTime',
        'greater_than',
        'LAST_N_DAYS:30',
        new List<String>{ 'At midnight', 'Today' }
      ),
      new LiveCase(
        Task.SObjectType,
        'Subject',
        'ReminderDateTime',
        'less_than',
        'LAST_N_DAYS:29',
        new List<String>{ 'Second before' }
      )
    };

    for (LiveCase c : cases) {
      String fieldName = c.rule.field.getName();
      String selectFrom =
        'SELECT ' +
        c.titleField +
        (fieldName == c.titleField ? '' : ', ' + fieldName) +
        ' FROM ' +
        c.objectName;
      Map<String, Object> binds = new Map<String, Object>();
      String query =
        selectFrom +
        SearchQueryBuilder.buildWhere(
          new List<SearchQueryBuilder.Condition>{
            SearchQueryBuilder.fromRule(c.rule)
          },
          binds
        );
      List<String> fromQuery = new List<String>();
      for (
        SObject row : Database.queryWithBinds(
          query,
          binds,
          AccessLevel.USER_MODE
        )
      ) {
        fromQuery.add((String) row.get(c.titleField));
      }
      fromQuery.sort();
      Assert.areEqual(c.expected, fromQuery, 'Query: ' + query);

      List<String> fromBoost = new List<String>();
      for (SObject row : Database.query(selectFrom, AccessLevel.USER_MODE)) {
        if (BoostRuleEngine.matches(row, c.rule)) {
          fromBoost.add((String) row.get(c.titleField));
        }
      }
      fromBoost.sort();
      Assert.areEqual(fromQuery, fromBoost, 'Boost agrees with: ' + query);
    }
  }

  /** A rule run against real records, with the titles it should select (sorted). */
  private class LiveCase {
    String objectName;
    String titleField;
    SearchTarget.FieldRule rule;
    List<String> expected;

    LiveCase(
      Schema.SObjectType type,
      String titleField,
      String field,
      String operator,
      String value,
      List<String> expected
    ) {
      this.objectName = type.getDescribe(SObjectDescribeOptions.DEFERRED)
        .getName();
      this.titleField = titleField;
      this.rule = validFilter(type, field, operator, value);
      this.expected = expected;
    }
  }

  @IsTest
  static void newOperatorsAreValidSosl() {
    // Runs the SOSL with every new condition (results are empty in tests without
    // setFixedSearchResults). The same clauses were also run for real against demo data in a
    // scratch org, see docs/PROGRESS.md (M8).
    RelativeDateParser.todayOverride = Date.today();
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      2
    );
    SearchConfig.ObjectConfig accounts = accountConfig();
    accounts.filterRules.add(ruleConfig('Website', 'is_blank', null));
    accounts.filterRules.add(ruleConfig('Industry', 'is_not_blank', null));
    accounts.filterRules.add(
      ruleConfig('Industry', 'in', industries[0] + ';' + industries[1])
    );
    accounts.filterRules.add(ruleConfig('Name', 'in', 'a;x\' OR Name != \''));
    accounts.filterRules.add(ruleConfig('NumberOfEmployees', 'in', '1;2'));
    SearchConfig.ObjectConfig tasks = new SearchConfig.ObjectConfig();
    tasks.developerName = 'Tasks';
    tasks.objectApiName = 'Task';
    tasks.titleField = 'Subject';
    tasks.filterRules.add(
      ruleConfig('ReminderDateTime', 'greater_than', 'LAST_N_DAYS:30')
    );
    tasks.filterRules.add(ruleConfig('ActivityDate', 'less_than', 'TODAY'));
    SchemaValidator validator = new SchemaValidator();
    List<SearchTarget> targets = new List<SearchTarget>{
      validator.validate(accounts),
      validator.validate(tasks)
    };
    Schema.DescribeSObjectResult quickText = SearchTestFactory.multiSelectObject();
    if (quickText != null) {
      SearchConfig.ObjectConfig quickTexts = new SearchConfig.ObjectConfig();
      quickTexts.developerName = 'Quick_Texts';
      quickTexts.objectApiName = SearchTestFactory.MULTI_SELECT_OBJECT;
      quickTexts.titleField = 'Name';
      Schema.DescribeFieldResult channel = SearchTestFactory.multiSelectField();
      quickTexts.filterRules.add(
        ruleConfig(
          SearchTestFactory.MULTI_SELECT_FIELD,
          'in',
          channel.getPicklistValues()[0].getValue() +
            ';' +
            channel.getPicklistValues()[1].getValue()
        )
      );
      quickTexts.filterRules.add(
        ruleConfig(SearchTestFactory.MULTI_SELECT_FIELD, 'is_not_blank', null)
      );
      targets.add(validator.validate(quickTexts));
    }
    for (SearchTarget target : targets) {
      Assert.isNotNull(target, 'Every test config should be valid');
    }

    String sosl = SearchQueryBuilder.buildSosl('printer', targets, null, 5);

    Assert.isNotNull(Search.query(sosl, AccessLevel.USER_MODE), sosl);
    // The multi-select conditions also run as SOQL (binds), including INCLUDES with binds.
    if (quickText != null) {
      SearchQueryBuilder.QuerySpec spec = SearchQueryBuilder.buildSoql(
        targets[2],
        null,
        5
      );
      Assert.isNotNull(
        Database.queryWithBinds(spec.query, spec.binds, AccessLevel.USER_MODE),
        spec.query
      );
    }
  }

  @IsTest
  static void buildSoqlSortsByIdWhenTitleIsNotSortable() {
    SearchConfig.ObjectConfig objectConfig = accountConfig();
    objectConfig.titleField = 'Description'; // Long text area: not sortable
    objectConfig.detailFields.clear();
    SearchTarget target = new SchemaValidator().validate(objectConfig);

    SearchQueryBuilder.QuerySpec spec = SearchQueryBuilder.buildSoql(
      target,
      null,
      3
    );

    Assert.areEqual(
      'SELECT Id, Description FROM Account ORDER BY Id ASC LIMIT 3',
      spec.query
    );
    Assert.isTrue(spec.binds.isEmpty());
  }
}
