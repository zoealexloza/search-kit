@IsTest
private class SchemaValidatorTest {
  private static SearchConfig.ObjectConfig objectConfig(
    String objectApiName,
    String titleField
  ) {
    SearchConfig.ObjectConfig objectConfig = new SearchConfig.ObjectConfig();
    objectConfig.developerName = 'Test_Object';
    objectConfig.objectApiName = objectApiName;
    objectConfig.titleField = titleField;
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
    rule.points = 10;
    return rule;
  }

  private static SearchConfig.FacetConfig facetConfig(
    String field,
    String label
  ) {
    SearchConfig.FacetConfig facet = new SearchConfig.FacetConfig();
    facet.developerName = 'Facet';
    facet.fieldApiName = field;
    facet.label = label;
    return facet;
  }

  private static SearchTarget.FieldRule filter(
    Schema.SObjectType type,
    String field,
    String operator,
    String value
  ) {
    return new SchemaValidator()
      .validateRule(
        type.getDescribe(),
        ruleConfig(field, operator, value),
        true
      );
  }

  private static SearchTarget.FieldRule boost(
    Schema.SObjectType type,
    String field,
    String operator,
    String value
  ) {
    return new SchemaValidator()
      .validateRule(
        type.getDescribe(),
        ruleConfig(field, operator, value),
        false
      );
  }

  // ---- objects and fields ----

  @IsTest
  static void validObjectUsesCanonicalNames() {
    String industry = SearchTestFactory.picklistValues(Account.Industry, 1)[0];
    SearchConfig.ObjectConfig config = objectConfig('account', 'name');
    config.detailFields = new List<String>{ 'industry', 'ANNUALREVENUE' };
    config.filterRules.add(
      ruleConfig('industry', 'EQUALS', industry.toUpperCase())
    );
    config.boostRules.add(ruleConfig('description', 'contains', 'priority'));
    config.facets.add(facetConfig('industry', null));
    config.iconName = 'standard:account';

    SearchTarget target = new SchemaValidator().validate(config);

    Assert.areEqual('Account', target.objectApiName);
    Assert.areEqual('Name', target.titleField.getName());
    Assert.areEqual(2, target.detailFields.size());
    Assert.areEqual('AnnualRevenue', target.detailFields[1].getName());
    Assert.areEqual(
      industry,
      target.filterRules[0].value,
      'Picklist value is stored in its canonical spelling'
    );
    Assert.areEqual(SchemaValidator.OP_EQUALS, target.filterRules[0].operator);
    Assert.areEqual(1, target.boostRules.size());
    Assert.areEqual(
      Account.Industry.getDescribe().getLabel(),
      target.facets[0].label,
      'Facet label defaults to the field label'
    );
    Assert.areEqual(
      Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
        .getLabelPlural(),
      target.sectionLabel,
      'Section label defaults to the plural object label'
    );
    Assert.areEqual('standard:account', target.iconName);
  }

  @IsTest
  static void unknownOrMalformedObjectIsSkipped() {
    SchemaValidator validator = new SchemaValidator();
    List<String> badNames = new List<String>{
      null,
      '',
      'Not_A_Real_Object__c',
      'Account; DELETE',
      'Account WHERE',
      'Account.Name',
      '1Account',
      'Account\'',
      'A'.repeat(81)
    };
    for (String name : badNames) {
      Assert.isNull(
        validator.validate(objectConfig(name, 'Name')),
        'Should skip object: ' + name
      );
    }
  }

  @IsTest
  static void invalidTitleFieldSkipsObject() {
    SchemaValidator validator = new SchemaValidator();
    for (
      String title : new List<String>{
        null,
        'Not_A_Field__c',
        'Owner.Name',
        'Name, Phone',
        'Name FROM User--'
      }
    ) {
      Assert.isNull(
        validator.validate(objectConfig('Account', title)),
        'Should skip for title: ' + title
      );
    }
  }

  @IsTest
  static void invalidDetailFieldIsSkippedOnly() {
    SearchConfig.ObjectConfig config = objectConfig('Account', 'Name');
    config.detailFields = new List<String>{ 'Missing__c', 'Phone', 'Bad Name' };

    SearchTarget target = new SchemaValidator().validate(config);

    Assert.areEqual(1, target.detailFields.size());
    Assert.areEqual('Phone', target.detailFields[0].getName());
  }

  @IsTest
  static void invalidFilterRuleSkipsWholeObject() {
    // Fail closed: a broken filter must not silently widen what visitors can see.
    SearchConfig.ObjectConfig config = objectConfig('Account', 'Name');
    config.filterRules.add(
      ruleConfig('Industry', 'equals', 'Not an active industry value')
    );
    Assert.isNull(new SchemaValidator().validate(config));
  }

  @IsTest
  static void invalidBoostRuleAndFacetAreSkippedOnly() {
    SearchConfig.ObjectConfig config = objectConfig('Account', 'Name');
    config.boostRules.add(ruleConfig('Missing__c', 'equals', 'x'));
    config.boostRules.add(ruleConfig('Name', 'contains', 'Acme'));
    config.facets.add(facetConfig('Name', null)); // text field: not a facet type
    config.facets.add(facetConfig('Missing__c', null));
    config.facets.add(facetConfig('Industry', 'Sector'));
    config.facets.add(facetConfig('INDUSTRY', 'Duplicate')); // same field twice

    SearchTarget target = new SchemaValidator().validate(config);

    Assert.areEqual(1, target.boostRules.size());
    Assert.areEqual('Name', target.boostRules[0].field.getName());
    Assert.areEqual(1, target.facets.size());
    Assert.areEqual('Sector', target.facets[0].label);
  }

  @IsTest
  static void validateAllSkipsInvalidAndDuplicateObjects() {
    List<SearchConfig.ObjectConfig> configs = new List<SearchConfig.ObjectConfig>{
      objectConfig('Account', 'Name'),
      objectConfig('Nope__c', 'Name'),
      objectConfig('ACCOUNT', 'Phone'),
      objectConfig('Contact', 'LastName')
    };

    List<SearchTarget> targets = new SchemaValidator().validateAll(configs);

    Assert.areEqual(2, targets.size());
    Assert.areEqual('Account', targets[0].objectApiName);
    Assert.areEqual(
      'Name',
      targets[0].titleField.getName(),
      'First config for an object wins'
    );
    Assert.areEqual('Contact', targets[1].objectApiName);
  }

  @IsTest
  static void nonSearchableObjectIsSkipped() {
    // Custom Metadata types are queryable but not searchable with SOSL.
    Assert.isNull(
      new SchemaValidator()
        .validate(objectConfig('Search_Config__mdt', 'DeveloperName'))
    );
  }

  // ---- rules: operator and type combinations ----

  @IsTest
  static void filterOperatorsMustSuitTheFieldType() {
    String industry = SearchTestFactory.picklistValues(Account.Industry, 1)[0];
    // Allowed
    Assert.isNotNull(
      filter(Account.SObjectType, 'Industry', 'equals', industry)
    );
    Assert.isNotNull(
      filter(Account.SObjectType, 'Industry', 'not_equals', industry)
    );
    Assert.isNotNull(filter(Account.SObjectType, 'Name', 'equals', 'Acme'));
    Assert.isNotNull(
      filter(Account.SObjectType, 'NumberOfEmployees', 'greater_than', '10')
    );
    Assert.isNotNull(
      filter(Account.SObjectType, 'AnnualRevenue', 'less_than', '1000.50')
    );
    Assert.isNotNull(
      filter(Contact.SObjectType, 'Birthdate', 'greater_than', '2000-01-31')
    );
    Assert.isNotNull(filter(Case.SObjectType, 'IsEscalated', 'is_true', null));
    Assert.isNotNull(
      filter(Case.SObjectType, 'IsEscalated', 'is_false', 'ignored')
    );
    Assert.isNotNull(filter(Case.SObjectType, 'IsEscalated', 'equals', 'TRUE'));
    Assert.isNotNull(
      filter(
        Task.SObjectType,
        'ReminderDateTime',
        'greater_than',
        '2026-01-01T00:00:00Z'
      )
    );
    // Not allowed
    Assert.isNull(
      filter(Account.SObjectType, 'Name', 'contains', 'Acme'),
      'contains is boost-only'
    );
    Assert.isNull(
      filter(Account.SObjectType, 'Name', 'starts_with', 'A'),
      'unknown operator'
    );
    Assert.isNull(
      filter(Account.SObjectType, 'Name', null, 'A'),
      'missing operator'
    );
    Assert.isNull(
      filter(Account.SObjectType, 'Name', 'greater_than', 'A'),
      'greater_than needs a number or date'
    );
    Assert.isNull(
      filter(Account.SObjectType, 'Industry', 'includes', industry),
      'includes needs a multi-select picklist'
    );
    Assert.isNull(
      filter(Account.SObjectType, 'Name', 'is_true', null),
      'is_true needs a checkbox'
    );
    Assert.isNull(
      filter(Account.SObjectType, 'Description', 'equals', 'x'),
      'long text is not filterable'
    );
    Assert.isNull(
      filter(Account.SObjectType, 'Name', 'equals', ''),
      'equals needs a value'
    );
    Assert.isNull(
      filter(Account.SObjectType, 'Missing__c', 'equals', 'x'),
      'unknown field'
    );
  }

  @IsTest
  static void boostRulesAllowContainsAndLongText() {
    Assert.isNotNull(
      boost(Account.SObjectType, 'Description', 'contains', 'urgent')
    );
    Assert.isNotNull(
      boost(Account.SObjectType, 'Industry', 'contains', 'tech')
    );
    Assert.isNull(
      boost(Account.SObjectType, 'NumberOfEmployees', 'contains', '5'),
      'contains needs text'
    );
    Assert.isNull(
      boost(Account.SObjectType, 'Description', 'contains', '  '),
      'contains needs a value'
    );
  }

  @IsTest
  static void ruleValuesAreTypeChecked() {
    Assert.isNull(
      filter(Account.SObjectType, 'NumberOfEmployees', 'equals', 'ten')
    );
    Assert.isNull(
      filter(
        Account.SObjectType,
        'NumberOfEmployees',
        'equals',
        '5 OR Id != null'
      )
    );
    Assert.isNull(
      filter(Contact.SObjectType, 'Birthdate', 'equals', '01/31/2000')
    );
    Assert.isNull(
      filter(
        Contact.SObjectType,
        'Birthdate',
        'equals',
        '2000-01-31 OR Id != null'
      )
    );
    Assert.isNull(filter(Case.SObjectType, 'IsEscalated', 'equals', 'yes'));
    Assert.isNull(
      filter(Task.SObjectType, 'ReminderDateTime', 'equals', '2026-01-01')
    );
    Assert.isNull(
      filter(
        Task.SObjectType,
        'ReminderDateTime',
        'equals',
        '2026-01-01T00:00:00Z\' OR Id != null'
      )
    );
    Assert.isNull(
      filter(Contact.SObjectType, 'AccountId', 'equals', 'not-an-id')
    );
    Assert.isNull(
      filter(Account.SObjectType, 'NumberOfEmployees', 'equals', '10.5'),
      'Integer field needs a whole number'
    );
    Assert.isNull(
      filter(Account.SObjectType, 'NumberOfEmployees', 'equals', '99999999999'),
      'Out of Integer range'
    );
    Assert.isNull(
      filter(Contact.SObjectType, 'Birthdate', 'equals', '2026-13-45'),
      'Right shape, impossible date'
    );
    Assert.isNull(
      filter(
        Task.SObjectType,
        'ReminderDateTime',
        'equals',
        '2026-13-45T99:99:99Z'
      ),
      'Right shape, impossible datetime'
    );
  }

  @IsTest
  static void parseTypedValueConvertsEachSupportedType() {
    Assert.areEqual(
      true,
      SchemaValidator.parseTypedValue(Case.IsEscalated.getDescribe(), ' True ')
    );
    Assert.areEqual(
      false,
      SchemaValidator.parseTypedValue(Case.IsEscalated.getDescribe(), 'false')
    );
    Assert.areEqual(
      Decimal.valueOf('-12.5'),
      SchemaValidator.parseTypedValue(
        Account.AnnualRevenue.getDescribe(),
        '-12.5'
      )
    );
    Assert.areEqual(
      Date.newInstance(2000, 1, 31),
      SchemaValidator.parseTypedValue(
        Contact.Birthdate.getDescribe(),
        '2000-01-31'
      )
    );
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 1, 1, 8, 30, 0),
      SchemaValidator.parseTypedValue(
        Task.ReminderDateTime.getDescribe(),
        '2026-01-01T08:30:00Z'
      )
    );
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 1, 1, 6, 30, 0),
      SchemaValidator.parseTypedValue(
        Task.ReminderDateTime.getDescribe(),
        '2026-01-01T08:30:00+02:00'
      )
    );
    Assert.areEqual(
      'Acme',
      SchemaValidator.parseTypedValue(Account.Name.getDescribe(), '  Acme ')
    );
    Id ownerId = UserInfo.getUserId();
    Assert.areEqual(
      String.valueOf(ownerId),
      SchemaValidator.parseTypedValue(
        Account.OwnerId.getDescribe(),
        String.valueOf(ownerId).left(15)
      )
    );
    Assert.isNull(
      SchemaValidator.parseTypedValue(Account.Name.getDescribe(), null)
    );
    Assert.isNull(
      SchemaValidator.parseTypedValue(
        Account.BillingAddress.getDescribe(),
        'x'
      ),
      'Compound address fields are not supported'
    );
  }

  @IsTest
  static void canonicalPicklistValueOnlyAcceptsActiveValues() {
    String industry = SearchTestFactory.picklistValues(Account.Industry, 1)[0];
    Schema.DescribeFieldResult field = Account.Industry.getDescribe();
    Assert.areEqual(
      industry,
      SchemaValidator.canonicalPicklistValue(
        field,
        ' ' + industry.toLowerCase() + ' '
      )
    );
    Assert.isNull(SchemaValidator.canonicalPicklistValue(field, 'Not a value'));
    Assert.isNull(
      SchemaValidator.canonicalPicklistValue(
        field,
        industry + '\' OR Name != \''
      )
    );
    Assert.isNull(SchemaValidator.canonicalPicklistValue(field, null));
  }

  // ---- M8 operators: is_blank, is_not_blank, in, relative dates ----

  /** One row of the operator x field type table. */
  private class RuleCase {
    Schema.DescribeSObjectResult objectDescribe;
    String field;
    String operator;
    String value;
    Boolean isFilter;
    Boolean valid;

    RuleCase(
      Schema.SObjectType type,
      String field,
      String operator,
      String value,
      Boolean isFilter,
      Boolean valid
    ) {
      this(type.getDescribe(), field, operator, value, isFilter, valid);
    }

    RuleCase(
      Schema.DescribeSObjectResult objectDescribe,
      String field,
      String operator,
      String value,
      Boolean isFilter,
      Boolean valid
    ) {
      this.objectDescribe = objectDescribe;
      this.field = field;
      this.operator = operator;
      this.value = value;
      this.isFilter = isFilter;
      this.valid = valid;
    }

    SearchTarget.FieldRule run() {
      return new SchemaValidator()
        .validateRule(
          objectDescribe,
          ruleConfig(field, operator, value),
          isFilter
        );
    }

    String describeCase() {
      return (isFilter ? 'filter ' : 'boost ') +
        objectDescribe.getName() +
        '.' +
        field +
        ' ' +
        operator +
        ' [' +
        value +
        ']';
    }
  }

  private static void assertCases(List<RuleCase> cases) {
    for (RuleCase c : cases) {
      SearchTarget.FieldRule rule = c.run();
      Assert.areEqual(
        c.valid,
        rule != null,
        (c.valid ? 'Should accept ' : 'Should reject ') + c.describeCase()
      );
    }
  }

  @IsTest
  static void blankOperatorsByFieldType() {
    List<RuleCase> cases = new List<RuleCase>();
    for (String op : new List<String>{ 'is_blank', 'is_not_blank' }) {
      // Every supported type except checkbox.
      cases.add(
        new RuleCase(Account.SObjectType, 'Name', op, null, true, true)
      );
      cases.add(
        new RuleCase(Contact.SObjectType, 'Email', op, null, true, true)
      );
      cases.add(
        new RuleCase(Account.SObjectType, 'Industry', op, null, true, true)
      );
      cases.add(
        new RuleCase(
          Account.SObjectType,
          'NumberOfEmployees',
          op,
          null,
          true,
          true
        )
      );
      cases.add(
        new RuleCase(Account.SObjectType, 'AnnualRevenue', op, null, true, true)
      );
      cases.add(
        new RuleCase(Contact.SObjectType, 'Birthdate', op, null, true, true)
      );
      cases.add(
        new RuleCase(Task.SObjectType, 'ReminderDateTime', op, null, true, true)
      );
      cases.add(
        new RuleCase(Contact.SObjectType, 'AccountId', op, null, true, true)
      );
      cases.add(
        new RuleCase(
          Account.SObjectType,
          'Name',
          op,
          'value is ignored',
          true,
          true
        )
      );
      // Long text: not filterable, but fine for a boost (evaluated in Apex).
      cases.add(
        new RuleCase(Account.SObjectType, 'Description', op, null, true, false)
      );
      cases.add(
        new RuleCase(Account.SObjectType, 'Description', op, null, false, true)
      );
      // Checkboxes are never blank.
      cases.add(
        new RuleCase(Case.SObjectType, 'IsEscalated', op, null, true, false)
      );
      cases.add(
        new RuleCase(Case.SObjectType, 'IsEscalated', op, null, false, false)
      );
      cases.add(
        new RuleCase(Account.SObjectType, 'Missing__c', op, null, true, false)
      );
      cases.add(
        new RuleCase(
          Account.SObjectType,
          'BillingAddress',
          op,
          null,
          false,
          false
        )
      );
    }
    Schema.DescribeSObjectResult quickText = SearchTestFactory.multiSelectObject();
    if (quickText != null) {
      cases.add(
        new RuleCase(quickText, 'Channel', 'is_blank', null, true, true)
      );
      cases.add(
        new RuleCase(quickText, 'Channel', 'is_not_blank', null, true, true)
      );
    }
    assertCases(cases);

    SearchTarget.FieldRule rule = filter(
      Account.SObjectType,
      'Name',
      'IS_BLANK',
      'ignored'
    );
    Assert.areEqual(SchemaValidator.OP_IS_BLANK, rule.operator);
    Assert.isNull(rule.value, 'is_blank has no value');
  }

  @IsTest
  static void inOperatorByFieldType() {
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      2
    );
    String twoIndustries = industries[0] + ';' + industries[1];
    String ownerId = String.valueOf(UserInfo.getUserId());
    List<RuleCase> cases = new List<RuleCase>{
      // Allowed: text, picklist, numbers, Ids
      new RuleCase(
        Account.SObjectType,
        'Industry',
        'in',
        twoIndustries,
        true,
        true
      ),
      new RuleCase(
        Account.SObjectType,
        'Industry',
        'in',
        industries[0],
        true,
        true
      ),
      new RuleCase(
        Account.SObjectType,
        'Name',
        'in',
        'Acme;Globex',
        true,
        true
      ),
      new RuleCase(
        Contact.SObjectType,
        'Email',
        'in',
        'a@example.com;b@example.com',
        true,
        true
      ),
      new RuleCase(
        Account.SObjectType,
        'NumberOfEmployees',
        'in',
        '10;20',
        true,
        true
      ),
      new RuleCase(
        Account.SObjectType,
        'AnnualRevenue',
        'in',
        '1.5;-2',
        true,
        true
      ),
      new RuleCase(
        Contact.SObjectType,
        'OwnerId',
        'in',
        ownerId + ';' + ownerId.left(15),
        true,
        true
      ),
      new RuleCase(
        Account.SObjectType,
        'Description',
        'in',
        'x;y',
        false,
        true
      ),
      // Not allowed: types that are compared rather than listed
      new RuleCase(
        Case.SObjectType,
        'IsEscalated',
        'in',
        'true;false',
        true,
        false
      ),
      new RuleCase(
        Contact.SObjectType,
        'Birthdate',
        'in',
        '2000-01-01;2000-01-02',
        true,
        false
      ),
      new RuleCase(
        Contact.SObjectType,
        'Birthdate',
        'in',
        'TODAY',
        true,
        false
      ),
      new RuleCase(
        Task.SObjectType,
        'ReminderDateTime',
        'in',
        '2026-01-01T00:00:00Z',
        true,
        false
      ),
      new RuleCase(
        Account.SObjectType,
        'Description',
        'in',
        'x;y',
        true,
        false
      ),
      // Not allowed: missing or invalid values. One bad value rejects the whole rule.
      new RuleCase(Account.SObjectType, 'Name', 'in', null, true, false),
      new RuleCase(Account.SObjectType, 'Name', 'in', ' ; ;', true, false),
      new RuleCase(
        Account.SObjectType,
        'Industry',
        'in',
        industries[0] + ';Not an industry',
        true,
        false
      ),
      new RuleCase(
        Account.SObjectType,
        'NumberOfEmployees',
        'in',
        '10;ten',
        true,
        false
      ),
      new RuleCase(
        Account.SObjectType,
        'NumberOfEmployees',
        'in',
        '10;5 OR Id != null',
        true,
        false
      ),
      new RuleCase(
        Account.SObjectType,
        'NumberOfEmployees',
        'in',
        '10;10.5',
        true,
        false
      ),
      new RuleCase(
        Account.SObjectType,
        'Industry',
        'in',
        industries[0] + '\' OR Name != \'',
        true,
        false
      ),
      new RuleCase(
        Contact.SObjectType,
        'OwnerId',
        'in',
        ownerId + ';not-an-id',
        true,
        false
      )
    };
    Schema.DescribeSObjectResult quickText = SearchTestFactory.multiSelectObject();
    if (quickText != null) {
      Schema.DescribeFieldResult channel = SearchTestFactory.multiSelectField();
      String channels =
        channel.getPicklistValues()[0].getValue() +
        ';' +
        channel.getPicklistValues()[1].getValue();
      cases.add(new RuleCase(quickText, 'Channel', 'in', channels, true, true));
      cases.add(
        new RuleCase(quickText, 'Channel', 'in', 'Not a channel', true, false)
      );
      // Existing multi-select rules, now testable with a real multi-select field.
      String oneChannel = channel.getPicklistValues()[0].getValue();
      cases.add(
        new RuleCase(quickText, 'Channel', 'includes', oneChannel, true, true)
      );
      cases.add(
        new RuleCase(quickText, 'Channel', 'equals', oneChannel, true, false)
      );
    }
    assertCases(cases);
    Assert.areEqual(
      2,
      ((List<Object>) filter(
            Account.SObjectType,
            'Industry',
            'in',
            twoIndustries
          )
          .value)
        .size(),
      'An in rule holds a list of typed values'
    );
  }

  @IsTest
  static void inOperatorConvertsTrimsAndDeduplicates() {
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      2
    );
    SearchTarget.FieldRule picklistRule = filter(
      Account.SObjectType,
      'Industry',
      'in',
      ' ' +
        industries[0].toUpperCase() +
        ' ;' +
        industries[0] +
        ';' +
        industries[1] +
        ';'
    );
    Assert.areEqual(
      new List<Object>{ industries[0], industries[1] },
      picklistRule.value,
      'Canonical spelling, duplicates and empty parts removed, order kept'
    );

    SearchTarget.FieldRule numberRule = filter(
      Account.SObjectType,
      'NumberOfEmployees',
      'in',
      '20;10;20'
    );
    Assert.areEqual(new List<Object>{ 20, 10 }, numberRule.value);
    Assert.isTrue(
      ((List<Object>) numberRule.value)[0] instanceof Integer,
      'Integer field gets Integer values, as for equals'
    );

    SearchTarget.FieldRule textRule = filter(
      Account.SObjectType,
      'Name',
      'in',
      'Acme;O\'Brien\'s'
    );
    Assert.areEqual(
      new List<Object>{ 'Acme', 'O\'Brien\'s' },
      textRule.value,
      'Text values are kept as typed; the query builder binds or escapes them'
    );
  }

  @IsTest
  static void relativeDatesByFieldTypeAndOperator() {
    RelativeDateParser.todayOverride = Date.newInstance(2026, 3, 1);
    List<RuleCase> cases = new List<RuleCase>();
    // Date fields: every comparison operator.
    for (
      String op : new List<String>{
        'equals',
        'not_equals',
        'greater_than',
        'less_than'
      }
    ) {
      for (
        String value : new List<String>{
          'TODAY',
          'yesterday',
          'LAST_N_DAYS:30',
          'NEXT_N_DAYS:7'
        }
      ) {
        cases.add(
          new RuleCase(Contact.SObjectType, 'Birthdate', op, value, true, true)
        );
      }
    }
    // Datetime fields: greater_than and less_than (equals would need a range).
    cases.add(
      new RuleCase(
        Task.SObjectType,
        'ReminderDateTime',
        'greater_than',
        'LAST_N_DAYS:30',
        true,
        true
      )
    );
    cases.add(
      new RuleCase(
        Task.SObjectType,
        'ReminderDateTime',
        'less_than',
        'TODAY',
        false,
        true
      )
    );
    cases.add(
      new RuleCase(
        Task.SObjectType,
        'ReminderDateTime',
        'equals',
        'TODAY',
        true,
        false
      )
    );
    cases.add(
      new RuleCase(
        Task.SObjectType,
        'ReminderDateTime',
        'not_equals',
        'YESTERDAY',
        false,
        false
      )
    );
    // Invalid values and injection attempts.
    for (
      String value : new List<String>{
        'LAST_N_DAYS:-1',
        'LAST_N_DAYS:abc',
        'LAST_N_DAYS:10000',
        'LAST_N_DAYS:30 OR Id != null',
        'TODAY\' OR Name != \'',
        'TOMORROW'
      }
    ) {
      cases.add(
        new RuleCase(
          Contact.SObjectType,
          'Birthdate',
          'greater_than',
          value,
          true,
          false
        )
      );
      cases.add(
        new RuleCase(
          Task.SObjectType,
          'ReminderDateTime',
          'greater_than',
          value,
          true,
          false
        )
      );
    }
    // Only date fields resolve relative dates.
    cases.add(
      new RuleCase(
        Account.SObjectType,
        'NumberOfEmployees',
        'greater_than',
        'LAST_N_DAYS:30',
        true,
        false
      )
    );
    cases.add(
      new RuleCase(
        Contact.SObjectType,
        'Birthdate',
        'is_true',
        'TODAY',
        true,
        false
      )
    );
    cases.add(
      new RuleCase(
        Contact.SObjectType,
        'Birthdate',
        'contains',
        'TODAY',
        false,
        false
      )
    );
    assertCases(cases);

    SearchTarget.FieldRule textRule = filter(
      Account.SObjectType,
      'Name',
      'equals',
      'TODAY'
    );
    Assert.areEqual(
      'TODAY',
      textRule.value,
      'On a text field TODAY is just text'
    );
  }

  @IsTest
  static void relativeDatesResolveToDaysAndDayBoundaries() {
    Date today = Date.newInstance(2026, 3, 1);
    RelativeDateParser.todayOverride = today;

    SearchTarget.FieldRule dateRule = filter(
      Contact.SObjectType,
      'Birthdate',
      'greater_than',
      'LAST_N_DAYS:30'
    );
    Assert.areEqual(SchemaValidator.OP_GREATER_THAN, dateRule.operator);
    Assert.areEqual(Date.newInstance(2026, 1, 30), dateRule.value);

    // Datetime greater_than day D: at or after the start of day D + 1, so the same days are
    // selected as on a Date field.
    SearchTarget.FieldRule after = filter(
      Task.SObjectType,
      'ReminderDateTime',
      'greater_than',
      'LAST_N_DAYS:30'
    );
    Assert.areEqual(SchemaValidator.OP_AT_OR_AFTER, after.operator);
    Assert.areEqual(
      RelativeDateParser.startOfDay(Date.newInstance(2026, 1, 31)),
      after.value
    );

    SearchTarget.FieldRule before = filter(
      Task.SObjectType,
      'ReminderDateTime',
      'less_than',
      'TODAY'
    );
    Assert.areEqual(SchemaValidator.OP_LESS_THAN, before.operator);
    Assert.areEqual(RelativeDateParser.startOfDay(today), before.value);

    // Resolved on every validation (each request), not once.
    RelativeDateParser.todayOverride = today.addDays(1);
    Assert.areEqual(
      Date.newInstance(2026, 1, 31),
      filter(Contact.SObjectType, 'Birthdate', 'greater_than', 'LAST_N_DAYS:30')
        .value
    );
  }

  @IsTest
  static void internalOperatorCannotBeConfigured() {
    Assert.isNull(
      filter(
        Task.SObjectType,
        'ReminderDateTime',
        SchemaValidator.OP_AT_OR_AFTER,
        '2026-01-01T00:00:00Z'
      )
    );
    Assert.isNull(
      boost(
        Task.SObjectType,
        'ReminderDateTime',
        SchemaValidator.OP_AT_OR_AFTER,
        '2026-01-01T00:00:00Z'
      )
    );
  }

  @IsTest
  static void invalidInFilterSkipsWholeObject() {
    // Fail closed applies to the new operators too.
    SearchConfig.ObjectConfig config = objectConfig('Account', 'Name');
    config.filterRules.add(ruleConfig('NumberOfEmployees', 'in', '10;ten'));
    Assert.isNull(new SchemaValidator().validate(config));
  }

  // ---- running user ----

  @IsTest
  static void objectWithoutReadAccessIsSkipped() {
    User guestLike = SearchTestFactory.minimumAccessUser(false);
    System.runAs(guestLike) {
      Assert.isNull(
        new SchemaValidator().validate(objectConfig('Account', 'Name')),
        'No Read on Account: object skipped'
      );
    }
  }

  @IsTest
  static void knowledgeWithoutAccessIsSkippedNotThrown() {
    // Describing Knowledge__kav throws NoAccessException for a user without Knowledge access
    // (and InvalidParameterValueException where Knowledge is off). Either way only that
    // object is skipped; the other objects of the config are still validated.
    User guestLike = SearchTestFactory.minimumAccessUser(true);
    System.runAs(guestLike) {
      SchemaValidator validator = new SchemaValidator();
      Assert.isNull(validator.describeObject('Knowledge__kav'));
      List<SearchTarget> targets = validator.validateAll(
        new List<SearchConfig.ObjectConfig>{
          objectConfig('Knowledge__kav', 'Title'),
          objectConfig('Account', 'Name')
        }
      );
      Assert.areEqual(1, targets.size(), 'Account is still searched');
      Assert.areEqual('Account', targets[0].objectApiName);
    }
  }

  @IsTest
  static void fieldsHiddenByFieldLevelSecurityAreSkipped() {
    // Read on Account but no field permissions: Name is readable, Industry is not.
    User restricted = SearchTestFactory.minimumAccessUser(true);
    String industry = SearchTestFactory.picklistValues(Account.Industry, 1)[0];
    System.runAs(restricted) {
      SearchConfig.ObjectConfig config = objectConfig('Account', 'Name');
      config.detailFields = new List<String>{ 'Industry' };
      config.boostRules.add(ruleConfig('Industry', 'equals', industry));
      config.facets.add(facetConfig('Industry', null));
      SearchTarget target = new SchemaValidator().validate(config);
      Assert.isNotNull(target, 'Object itself is still searchable');
      Assert.isTrue(
        target.detailFields.isEmpty(),
        'Hidden detail field skipped'
      );
      Assert.isTrue(
        target.boostRules.isEmpty(),
        'Boost rule on hidden field skipped'
      );
      Assert.isTrue(target.facets.isEmpty(), 'Facet on hidden field skipped');

      config.filterRules.add(ruleConfig('Industry', 'equals', industry));
      Assert.isNull(
        new SchemaValidator().validate(config),
        'Filter on a hidden field skips the object (fail closed)'
      );
    }
  }

  // ---- lookup detail fields ----

  @IsTest
  static void lookupDetailFieldsSelectTheRelatedName() {
    SearchConfig.ObjectConfig config = objectConfig('Case', 'Subject');
    config.detailFields = new List<String>{
      'accountid',
      'OwnerId',
      'ParentId',
      'Status'
    };
    SearchTarget target = new SchemaValidator().validate(config);

    Assert.areEqual(4, target.detailFields.size());
    SearchTarget.LookupName account = target.getLookupName(
      target.detailFields[0]
    );
    Assert.areEqual('Account.Name', account.path());
    Assert.areEqual(
      Case.AccountId.getDescribe().getLabel().removeEnd(' ID'),
      account.label
    );
    Assert.areEqual(
      'Owner.Name',
      target.getLookupName(target.detailFields[1]).path(),
      'Polymorphic owner (user or queue) goes through the Name object'
    );
    Assert.areEqual(
      'Parent.CaseNumber',
      target.getLookupName(target.detailFields[2]).path(),
      'Uses the related object\'s own name field'
    );
    Assert.isNull(target.getLookupName(target.detailFields[3]), 'Not a lookup');

    List<String> fields = target.getQueryFields();
    Assert.isTrue(fields.contains('Account.Name'));
    Assert.isTrue(fields.contains('Owner.Name'));
    Assert.isFalse(
      fields.contains('AccountId'),
      'The ID itself is not selected for display'
    );
  }

  @IsTest
  static void lookupToAnUnreadableObjectIsSkipped() {
    // No object permissions at all: Account (and so Case.AccountId's name) is not readable.
    User guestLike = SearchTestFactory.minimumAccessUser(false);
    System.runAs(guestLike) {
      Assert.isNull(
        new SchemaValidator().describeLookupName(Case.AccountId.getDescribe()),
        'A user-mode query on Account.Name would fail, so the lookup is dropped'
      );
    }
  }

  @IsTest
  static void lookupLabelDropsTheIdSuffixOnStandardLookups() {
    Assert.areEqual(
      Case.OwnerId.getDescribe().getLabel().removeEnd(' ID'),
      SchemaValidator.lookupLabel(Case.OwnerId.getDescribe())
    );
    Assert.areEqual(
      Account.Name.getDescribe().getLabel(),
      SchemaValidator.lookupLabel(Account.Name.getDescribe()),
      'Labels without the suffix are kept'
    );
  }

  @IsTest
  static void lookupDetailIsSkippedWhenTheRelatedObjectIsNotReadable() {
    // Read on Case and its AccountId field, but none on Account.
    User restricted = SearchTestFactory.minimumAccessUser(false);
    System.runAs(new User(Id = UserInfo.getUserId())) {
      PermissionSet permissionSet = new PermissionSet(
        Name = 'Lookup_Test_Case_Read',
        Label = 'Lookup Test Case Read'
      );
      insert permissionSet;
      insert new ObjectPermissions(
        ParentId = permissionSet.Id,
        SobjectType = 'Case',
        PermissionsRead = true
      );
      insert new FieldPermissions(
        ParentId = permissionSet.Id,
        SobjectType = 'Case',
        Field = 'Case.AccountId',
        PermissionsRead = true
      );
      insert new PermissionSetAssignment(
        AssigneeId = restricted.Id,
        PermissionSetId = permissionSet.Id
      );
    }
    System.runAs(restricted) {
      SearchConfig.ObjectConfig config = objectConfig('Case', 'CaseNumber');
      config.detailFields = new List<String>{ 'AccountId', 'OwnerId' };
      SearchTarget target = new SchemaValidator().validate(config);
      Assert.isNotNull(target, 'Case is still searchable');
      Assert.areEqual(1, target.detailFields.size());
      Assert.areEqual(
        'OwnerId',
        target.detailFields[0].getName(),
        'Account name is not readable, so only Owner is kept'
      );
      Assert.isFalse(target.getQueryFields().contains('Account.Name'));
      Assert.isFalse(
        target.getQueryFields().contains('AccountId'),
        'Never falls back to showing the ID'
      );
    }
  }

  // ---- facet Values allowlist ----

  @IsTest
  static void facetValuesKeepConfiguredOrderAndCanonicalSpelling() {
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      3
    );
    SearchConfig.FacetConfig config = facetConfig('Industry', null);
    // Reversed, lower case, padded, with a repeat, an unknown value and an empty slot.
    config.values =
      ' ' +
      industries[2].toLowerCase() +
      ' ;' +
      industries[0] +
      ';;Not_A_Value;' +
      industries[2];

    List<String> values = SchemaValidator.parseFacetValues(
      Account.Industry.getDescribe(),
      config
    );

    Assert.areEqual(
      new List<String>{ industries[2], industries[0] },
      values,
      'Configured order, canonical spelling, unknown and repeated values dropped'
    );
  }

  @IsTest
  static void blankFacetValuesOfferEverything() {
    Assert.isNull(
      SchemaValidator.parseFacetValues(
        Account.Industry.getDescribe(),
        facetConfig('Industry', null)
      )
    );
  }

  @IsTest
  static void checkboxFacetValuesAcceptTrueAndFalse() {
    SearchConfig.FacetConfig config = facetConfig('IsEscalated', null);
    config.values = 'TRUE;yes';
    Assert.areEqual(
      new List<String>{ 'true' },
      SchemaValidator.parseFacetValues(Case.IsEscalated.getDescribe(), config)
    );
  }

  @IsTest
  static void facetWithNoValidValuesIsSkipped() {
    SearchConfig.ObjectConfig config = objectConfig('Account', 'Name');
    SearchConfig.FacetConfig facet = facetConfig('Industry', null);
    facet.values = 'Not_A_Value;Also_Not';
    config.facets.add(facet);

    SearchTarget target = new SchemaValidator().validate(config);

    Assert.isTrue(
      target.facets.isEmpty(),
      'A list with nothing valid is a config mistake: the facet is not shown with all values'
    );
  }
}
