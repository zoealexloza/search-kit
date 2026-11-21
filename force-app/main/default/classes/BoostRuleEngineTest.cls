@IsTest
private class BoostRuleEngineTest {
  private static SearchTarget.FieldRule rule(
    Schema.SObjectField field,
    String operator,
    Object value,
    Integer points
  ) {
    SearchTarget.FieldRule rule = new SearchTarget.FieldRule();
    rule.field = field.getDescribe();
    rule.operator = operator;
    rule.value = value;
    rule.points = points;
    return rule;
  }

  /** One row of the scoring table. */
  private class ScoreCase {
    String name;
    Integer resultCount;
    Integer sourceIndex;
    SObject record;
    Integer expected;

    ScoreCase(
      String name,
      Integer resultCount,
      Integer sourceIndex,
      SObject record,
      Integer expected
    ) {
      this.name = name;
      this.resultCount = resultCount;
      this.sourceIndex = sourceIndex;
      this.record = record;
      this.expected = expected;
    }
  }

  @IsTest
  static void scoreFollowsFormulaForEveryCase() {
    String industry = SearchTestFactory.picklistValues(Account.Industry, 1)[0];
    List<SearchTarget.FieldRule> rules = new List<SearchTarget.FieldRule>{
      rule(
        Account.NumberOfEmployees,
        SchemaValidator.OP_GREATER_THAN,
        100.0,
        50
      ),
      rule(Account.Industry, SchemaValidator.OP_EQUALS, industry, 10),
      rule(Account.Name, SchemaValidator.OP_CONTAINS, 'demo', -20)
    };
    List<ScoreCase> cases = new List<ScoreCase>{
      new ScoreCase(
        'top result, no rules match',
        10,
        0,
        new Account(Name = 'A', NumberOfEmployees = 5),
        10
      ),
      new ScoreCase(
        'last result, no rules match',
        10,
        9,
        new Account(Name = 'A', NumberOfEmployees = 5),
        1
      ),
      new ScoreCase(
        'one rule matches',
        10,
        7,
        new Account(Name = 'A', NumberOfEmployees = 500),
        3 + 50
      ),
      new ScoreCase(
        'two rules match',
        10,
        7,
        new Account(Name = 'A', NumberOfEmployees = 500, Industry = industry),
        3 + 50 + 10
      ),
      new ScoreCase(
        'negative points demote',
        10,
        0,
        new Account(Name = 'Demo account'),
        10 - 20
      ),
      new ScoreCase(
        'all three rules',
        4,
        2,
        new Account(
          Name = 'DEMO',
          NumberOfEmployees = 101,
          Industry = industry
        ),
        2 + 50 + 10 - 20
      ),
      new ScoreCase('blank fields never match', 3, 0, new Account(), 3)
    };
    for (ScoreCase c : cases) {
      Assert.areEqual(
        c.expected,
        BoostRuleEngine.score(c.resultCount, c.sourceIndex, c.record, rules),
        c.name
      );
    }
  }

  @IsTest
  static void scoreWithNoRulesIsBaseScore() {
    Assert.areEqual(
      5,
      BoostRuleEngine.score(
        5,
        0,
        new Account(),
        new List<SearchTarget.FieldRule>()
      )
    );
  }

  @IsTest
  static void nullPointsCountAsZero() {
    SearchTarget.FieldRule noPoints = rule(
      Account.Name,
      SchemaValidator.OP_CONTAINS,
      'a',
      null
    );
    Assert.areEqual(
      2,
      BoostRuleEngine.score(
        2,
        0,
        new Account(Name = 'abc'),
        new List<SearchTarget.FieldRule>{ noPoints }
      )
    );
  }

  @IsTest
  static void rankMovesBoostedRecordUpAndKeepsOrderOtherwise() {
    // The example from the score() docblock: 10 results, Featured +50 at position 8.
    List<SObject> records = new List<SObject>();
    for (Integer i = 0; i < 10; i++) {
      records.add(
        new Account(Name = 'Result ' + i, NumberOfEmployees = i == 7 ? 1000 : 1)
      );
    }
    List<SearchTarget.FieldRule> rules = new List<SearchTarget.FieldRule>{
      rule(
        Account.NumberOfEmployees,
        SchemaValidator.OP_GREATER_THAN,
        100.0,
        50
      )
    };

    List<BoostRuleEngine.ScoredRecord> ranked = BoostRuleEngine.rank(
      records,
      rules
    );

    Assert.areEqual(
      'Result 7',
      ranked[0].record.get('Name'),
      'Boosted record moves to the top'
    );
    Assert.areEqual(53, ranked[0].score);
    Assert.areEqual(7, ranked[0].sourceIndex);
    List<String> rest = new List<String>();
    for (Integer i = 1; i < ranked.size(); i++) {
      rest.add((String) ranked[i].record.get('Name'));
    }
    Assert.areEqual(
      'Result 0,Result 1,Result 2,Result 3,Result 4,Result 5,Result 6,Result 8,Result 9',
      String.join(rest, ','),
      'Others keep relevance order'
    );
  }

  @IsTest
  static void rankBreaksTiesBySourceOrder() {
    // Index 0 (base 3) and index 2 (base 1 + 2 points) both score 3: index 0 stays first.
    List<SObject> records = new List<SObject>{
      new Account(Name = 'first'),
      new Account(Name = 'second'),
      new Account(Name = 'third boosted')
    };
    List<SearchTarget.FieldRule> rules = new List<SearchTarget.FieldRule>{
      rule(Account.Name, SchemaValidator.OP_CONTAINS, 'boosted', 2)
    };

    List<BoostRuleEngine.ScoredRecord> ranked = BoostRuleEngine.rank(
      records,
      rules
    );

    Assert.areEqual('first', ranked[0].record.get('Name'));
    Assert.areEqual('third boosted', ranked[1].record.get('Name'));
    Assert.areEqual('second', ranked[2].record.get('Name'));
  }

  @IsTest
  static void rankHandlesEmptyList() {
    Assert.isTrue(
      BoostRuleEngine.rank(
          new List<SObject>(),
          new List<SearchTarget.FieldRule>()
        )
        .isEmpty()
    );
  }

  @IsTest
  static void matchesTextOperatorsIgnoreCase() {
    Account record = new Account(
      Name = 'Getting Started',
      Description = 'Alpha;Beta'
    );
    Assert.isTrue(
      BoostRuleEngine.matches(
        record,
        rule(Account.Name, SchemaValidator.OP_EQUALS, 'getting started', 1)
      ),
      'equals ignores case'
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        record,
        rule(Account.Name, SchemaValidator.OP_EQUALS, 'getting', 1)
      )
    );
    Assert.isTrue(
      BoostRuleEngine.matches(
        record,
        rule(Account.Name, SchemaValidator.OP_NOT_EQUALS, 'other', 1)
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        record,
        rule(Account.Name, SchemaValidator.OP_NOT_EQUALS, 'GETTING STARTED', 1)
      )
    );
    Assert.isTrue(
      BoostRuleEngine.matches(
        record,
        rule(Account.Name, SchemaValidator.OP_CONTAINS, 'START', 1)
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        record,
        rule(Account.Name, SchemaValidator.OP_CONTAINS, 'finish', 1)
      )
    );
    // includes is checked on a ;-separated value, as multi-select picklists are stored.
    Assert.isTrue(
      BoostRuleEngine.matches(
        record,
        rule(Account.Description, SchemaValidator.OP_INCLUDES, 'beta', 1)
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        record,
        rule(Account.Description, SchemaValidator.OP_INCLUDES, 'Alp', 1)
      ),
      'includes matches whole values only'
    );
  }

  @IsTest
  static void matchesBlankFieldOnlyForNotEqualsAndIsFalse() {
    Account blank = new Account();
    Assert.isFalse(
      BoostRuleEngine.matches(
        blank,
        rule(Account.Name, SchemaValidator.OP_EQUALS, 'x', 1)
      )
    );
    Assert.isTrue(
      BoostRuleEngine.matches(
        blank,
        rule(Account.Name, SchemaValidator.OP_NOT_EQUALS, 'x', 1)
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        blank,
        rule(Account.Name, SchemaValidator.OP_CONTAINS, 'x', 1)
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        blank,
        rule(Account.Description, SchemaValidator.OP_INCLUDES, 'x', 1)
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        blank,
        rule(Account.NumberOfEmployees, SchemaValidator.OP_GREATER_THAN, 1.0, 1)
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        blank,
        rule(Account.NumberOfEmployees, SchemaValidator.OP_LESS_THAN, 1.0, 1)
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        new Case(),
        rule(Case.IsEscalated, SchemaValidator.OP_IS_TRUE, true, 1)
      )
    );
    Assert.isTrue(
      BoostRuleEngine.matches(
        new Case(),
        rule(Case.IsEscalated, SchemaValidator.OP_IS_FALSE, false, 1)
      )
    );
  }

  @IsTest
  static void matchesBooleans() {
    Case flagged = new Case(IsEscalated = true);
    Assert.isTrue(
      BoostRuleEngine.matches(
        flagged,
        rule(Case.IsEscalated, SchemaValidator.OP_IS_TRUE, true, 1)
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        flagged,
        rule(Case.IsEscalated, SchemaValidator.OP_IS_FALSE, false, 1)
      )
    );
    Assert.isTrue(
      BoostRuleEngine.matches(
        flagged,
        rule(Case.IsEscalated, SchemaValidator.OP_EQUALS, true, 1)
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        flagged,
        rule(Case.IsEscalated, SchemaValidator.OP_EQUALS, false, 1)
      )
    );
  }

  @IsTest
  static void matchesNumbersIncludingIntegerFields() {
    // NumberOfEmployees is an Integer field; rule values are always Decimal.
    Account record = new Account(
      NumberOfEmployees = 100,
      AnnualRevenue = 2500.50
    );
    Assert.isTrue(
      BoostRuleEngine.matches(
        record,
        rule(Account.NumberOfEmployees, SchemaValidator.OP_EQUALS, 100.0, 1)
      )
    );
    Assert.isTrue(
      BoostRuleEngine.matches(
        record,
        rule(
          Account.NumberOfEmployees,
          SchemaValidator.OP_GREATER_THAN,
          99.5,
          1
        )
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        record,
        rule(
          Account.NumberOfEmployees,
          SchemaValidator.OP_GREATER_THAN,
          100.0,
          1
        )
      )
    );
    Assert.isTrue(
      BoostRuleEngine.matches(
        record,
        rule(Account.AnnualRevenue, SchemaValidator.OP_LESS_THAN, 2500.51, 1)
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        record,
        rule(Account.AnnualRevenue, SchemaValidator.OP_LESS_THAN, 2500.50, 1)
      )
    );
    Assert.isTrue(
      BoostRuleEngine.matches(
        record,
        rule(Account.AnnualRevenue, SchemaValidator.OP_NOT_EQUALS, 1.0, 1)
      )
    );
  }

  @IsTest
  static void matchesDatesAndDatetimes() {
    Contact person = new Contact(Birthdate = Date.newInstance(2000, 6, 15));
    Assert.isTrue(
      BoostRuleEngine.matches(
        person,
        rule(
          Contact.Birthdate,
          SchemaValidator.OP_EQUALS,
          Date.newInstance(2000, 6, 15),
          1
        )
      )
    );
    Assert.isTrue(
      BoostRuleEngine.matches(
        person,
        rule(
          Contact.Birthdate,
          SchemaValidator.OP_GREATER_THAN,
          Date.newInstance(2000, 6, 14),
          1
        )
      )
    );
    Assert.isTrue(
      BoostRuleEngine.matches(
        person,
        rule(
          Contact.Birthdate,
          SchemaValidator.OP_LESS_THAN,
          Date.newInstance(2000, 6, 16),
          1
        )
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        person,
        rule(
          Contact.Birthdate,
          SchemaValidator.OP_LESS_THAN,
          Date.newInstance(2000, 6, 15),
          1
        )
      )
    );

    Datetime reminder = Datetime.newInstanceGmt(2026, 1, 1, 12, 0, 0);
    Task reminderTask = new Task(ReminderDateTime = reminder);
    Assert.isTrue(
      BoostRuleEngine.matches(
        reminderTask,
        rule(Task.ReminderDateTime, SchemaValidator.OP_EQUALS, reminder, 1)
      )
    );
    Assert.isTrue(
      BoostRuleEngine.matches(
        reminderTask,
        rule(
          Task.ReminderDateTime,
          SchemaValidator.OP_GREATER_THAN,
          reminder.addSeconds(-1),
          1
        )
      )
    );
    Assert.isTrue(
      BoostRuleEngine.matches(
        reminderTask,
        rule(
          Task.ReminderDateTime,
          SchemaValidator.OP_LESS_THAN,
          reminder.addSeconds(1),
          1
        )
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        reminderTask,
        rule(
          Task.ReminderDateTime,
          SchemaValidator.OP_GREATER_THAN,
          reminder,
          1
        )
      )
    );
  }

  @IsTest
  static void mismatchedTypesNeverMatch() {
    // A Datetime value compared with a Date rule value (and vice versa) is not comparable.
    Task reminderTask = new Task(
      ReminderDateTime = Datetime.now(),
      ActivityDate = Date.today()
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        reminderTask,
        rule(
          Task.ReminderDateTime,
          SchemaValidator.OP_GREATER_THAN,
          Date.today().addDays(-1),
          1
        )
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        reminderTask,
        rule(
          Task.ActivityDate,
          SchemaValidator.OP_GREATER_THAN,
          Datetime.now().addDays(-1),
          1
        )
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        reminderTask,
        rule(Task.ActivityDate, SchemaValidator.OP_GREATER_THAN, true, 1)
      )
    );
  }

  @IsTest
  static void matchesBlankOperators() {
    SearchTarget.FieldRule blank = rule(
      Account.Name,
      SchemaValidator.OP_IS_BLANK,
      null,
      1
    );
    SearchTarget.FieldRule notBlank = rule(
      Account.Name,
      SchemaValidator.OP_IS_NOT_BLANK,
      null,
      1
    );
    Map<String, Boolean> isBlankByName = new Map<String, Boolean>{
      'Acme' => false,
      ' x ' => false,
      '' => true,
      '   ' => true
    };
    for (String name : isBlankByName.keySet()) {
      Account record = new Account(Name = name);
      Assert.areEqual(
        isBlankByName.get(name),
        BoostRuleEngine.matches(record, blank),
        '[' + name + ']'
      );
      Assert.areEqual(
        !isBlankByName.get(name),
        BoostRuleEngine.matches(record, notBlank),
        '[' + name + ']'
      );
    }
    Assert.isTrue(BoostRuleEngine.matches(new Account(), blank), 'null');
    Assert.isTrue(
      BoostRuleEngine.matches(
        new Account(),
        rule(Account.NumberOfEmployees, SchemaValidator.OP_IS_BLANK, null, 1)
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        new Account(NumberOfEmployees = 0),
        rule(Account.NumberOfEmployees, SchemaValidator.OP_IS_BLANK, null, 1)
      ),
      'Zero is a value, not blank'
    );
  }

  @IsTest
  static void matchesInOperator() {
    SearchTarget.FieldRule textIn = rule(
      Account.Name,
      SchemaValidator.OP_IN,
      new List<Object>{ 'Acme', 'Globex' },
      1
    );
    Assert.isTrue(
      BoostRuleEngine.matches(new Account(Name = 'GLOBEX'), textIn)
    );
    Assert.isFalse(
      BoostRuleEngine.matches(new Account(Name = 'Acme Corp'), textIn)
    );
    Assert.isFalse(BoostRuleEngine.matches(new Account(), textIn));

    SearchTarget.FieldRule numberIn = rule(
      Account.NumberOfEmployees,
      SchemaValidator.OP_IN,
      new List<Object>{ 10, 20 },
      1
    );
    Assert.isTrue(
      BoostRuleEngine.matches(new Account(NumberOfEmployees = 20), numberIn)
    );
    Assert.isFalse(
      BoostRuleEngine.matches(new Account(NumberOfEmployees = 15), numberIn)
    );
  }

  @IsTest
  static void matchesInOnMultiSelectAsAnyOf() {
    Schema.DescribeFieldResult channel = SearchTestFactory.multiSelectField();
    if (channel == null) {
      return; // QuickText is not available in this org.
    }
    SearchTarget.FieldRule anyOf = new SearchTarget.FieldRule();
    anyOf.field = channel;
    anyOf.operator = SchemaValidator.OP_IN;
    anyOf.value = new List<Object>{ 'Email', 'Phone' };
    SObject record = SearchTestFactory.multiSelectObject()
      .getSObjectType()
      .newSObject();

    record.put(channel.getName(), 'Chat;phone');
    Assert.isTrue(BoostRuleEngine.matches(record, anyOf), 'One value matches');
    record.put(channel.getName(), 'Chat;Portal');
    Assert.isFalse(BoostRuleEngine.matches(record, anyOf), 'No value matches');
    record.put(channel.getName(), 'Emails');
    Assert.isFalse(
      BoostRuleEngine.matches(record, anyOf),
      'Whole values only, not substrings'
    );
  }

  @IsTest
  static void matchesAtOrAfterIncludesTheBoundary() {
    Datetime boundary = Datetime.newInstanceGmt(2026, 3, 1, 8, 0, 0);
    SearchTarget.FieldRule atOrAfter = rule(
      Task.ReminderDateTime,
      SchemaValidator.OP_AT_OR_AFTER,
      boundary,
      1
    );
    Assert.isTrue(
      BoostRuleEngine.matches(new Task(ReminderDateTime = boundary), atOrAfter)
    );
    Assert.isTrue(
      BoostRuleEngine.matches(
        new Task(ReminderDateTime = boundary.addSeconds(1)),
        atOrAfter
      )
    );
    Assert.isFalse(
      BoostRuleEngine.matches(
        new Task(ReminderDateTime = boundary.addSeconds(-1)),
        atOrAfter
      )
    );
    Assert.isFalse(BoostRuleEngine.matches(new Task(), atOrAfter));
  }

  @IsTest
  static void unknownOperatorNeverMatches() {
    Assert.isFalse(
      BoostRuleEngine.matches(
        new Account(Name = 'x'),
        rule(Account.Name, 'starts_with', 'x', 1)
      )
    );
  }
}
