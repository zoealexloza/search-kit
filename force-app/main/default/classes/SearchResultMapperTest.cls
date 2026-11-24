@IsTest
private class SearchResultMapperTest {
  @IsTest
  static void formatValueProducesDisplayText() {
    Schema.PicklistEntry industry = null;
    for (
      Schema.PicklistEntry entry : Account.Industry.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.isActive() && industry == null) {
        industry = entry;
      }
    }
    Date day = Date.newInstance(2026, 3, 4);
    Datetime moment = Datetime.newInstance(2026, 3, 4, 5, 6, 7);

    Assert.isNull(
      SearchResultMapper.formatValue(null, Account.Name.getDescribe())
    );
    Assert.areEqual(
      'Acme',
      SearchResultMapper.formatValue('Acme', Account.Name.getDescribe())
    );
    Assert.areEqual(
      System.Label.Search_Value_Yes,
      SearchResultMapper.formatValue(true, Case.IsEscalated.getDescribe())
    );
    Assert.areEqual(
      System.Label.Search_Value_No,
      SearchResultMapper.formatValue(false, Case.IsEscalated.getDescribe())
    );
    Assert.areEqual(
      industry.getLabel(),
      SearchResultMapper.formatValue(
        industry.getValue(),
        Account.Industry.getDescribe()
      )
    );
    Assert.areEqual(
      'Unknown value',
      SearchResultMapper.formatValue(
        'Unknown value',
        Account.Industry.getDescribe()
      ),
      'Unknown picklist value shown as is'
    );
    Assert.areEqual(
      day.format(),
      SearchResultMapper.formatValue(day, Contact.Birthdate.getDescribe())
    );
    Assert.areEqual(
      moment.format(),
      SearchResultMapper.formatValue(
        moment,
        Task.ReminderDateTime.getDescribe()
      )
    );
    Assert.areEqual(
      (1234.5).format(),
      SearchResultMapper.formatValue(
        1234.5,
        Account.AnnualRevenue.getDescribe()
      )
    );
    Assert.areEqual(
      '42',
      SearchResultMapper.formatValue(
        42,
        Account.NumberOfEmployees.getDescribe()
      )
    );
  }

  @IsTest
  static void formatValueShortensLongText() {
    String longText = 'x'.repeat(1000);
    String formatted = SearchResultMapper.formatValue(
      longText,
      Account.Description.getDescribe()
    );
    Assert.areEqual(SearchResultMapper.MAX_VALUE_LENGTH, formatted.length());
    Assert.isTrue(formatted.endsWith('...'));
  }

  @IsTest
  static void toGroupMapsRecordsAndSkipsBlankDetails() {
    SearchConfig.ObjectConfig config = new SearchConfig.ObjectConfig();
    config.developerName = 'Accounts';
    config.objectApiName = 'Account';
    config.titleField = 'Name';
    config.detailFields = new List<String>{ 'Phone', 'Website' };
    config.sectionLabel = 'Companies';
    config.iconName = 'standard:account';
    SearchTarget target = new SchemaValidator().validate(config);

    Account withTitle = new Account(
      Id = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
          .getKeyPrefix() + '000000000001',
      Name = 'Acme',
      Phone = '555-0100'
    );
    Account withoutTitle = new Account(
      Id = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
          .getKeyPrefix() + '000000000002'
    );
    List<BoostRuleEngine.ScoredRecord> ranked = new List<BoostRuleEngine.ScoredRecord>{
      new BoostRuleEngine.ScoredRecord(withTitle, 0, 12),
      new BoostRuleEngine.ScoredRecord(withoutTitle, 1, 1)
    };

    SearchResponseDto.ObjectGroup objectGroup = SearchResultMapper.toGroup(
      target,
      ranked,
      true
    );

    Assert.areEqual('Account', objectGroup.objectApiName);
    Assert.areEqual('Companies', objectGroup.sectionLabel);
    Assert.areEqual('standard:account', objectGroup.iconName);
    Assert.areEqual(2, objectGroup.totalShown);
    Assert.isTrue(objectGroup.hasMore);
    SearchResponseDto.Result first = objectGroup.results[0];
    Assert.areEqual(withTitle.Id, first.recordId);
    Assert.areEqual('Acme', first.title);
    Assert.areEqual(12, first.score);
    Assert.areEqual(1, first.details.size(), 'Blank Website left out');
    Assert.areEqual(
      Account.Phone.getDescribe().getLabel(),
      first.details[0].label
    );
    Assert.areEqual('555-0100', first.details[0].value);
    Assert.areEqual(System.Label.Search_Untitled, objectGroup.results[1].title);
    Assert.isTrue(objectGroup.results[1].details.isEmpty());
  }

  @IsTest
  static void formatValueJoinsMultiSelectLabels() {
    Schema.DescribeFieldResult channel = SearchTestFactory.multiSelectField();
    if (channel == null) {
      return; // QuickText is not available in this org.
    }
    List<Schema.PicklistEntry> entries = channel.getPicklistValues();
    Assert.areEqual(
      entries[0].getLabel() + '; ' + entries[1].getLabel(),
      SearchResultMapper.formatValue(
        entries[0].getValue() + ';' + entries[1].getValue(),
        channel
      )
    );
  }

  @IsTest
  static void toSearchableObjectsKeepsOrderAndLabels() {
    SearchConfig.ObjectConfig cases = new SearchConfig.ObjectConfig();
    cases.developerName = 'Cases';
    cases.objectApiName = 'Case';
    cases.titleField = 'Subject';
    cases.sectionLabel = 'My Cases';
    cases.iconName = 'standard:case';
    SearchConfig.FacetConfig status = new SearchConfig.FacetConfig();
    status.developerName = 'Status';
    status.fieldApiName = 'Status';
    cases.facets.add(status);
    SearchConfig.ObjectConfig accounts = new SearchConfig.ObjectConfig();
    accounts.developerName = 'Accounts';
    accounts.objectApiName = 'Account';
    accounts.titleField = 'Name';
    List<SearchTarget> targets = new SchemaValidator()
      .validateAll(new List<SearchConfig.ObjectConfig>{ cases, accounts });

    List<SearchResponseDto.SearchableObject> objects = SearchResultMapper.toSearchableObjects(
      targets
    );

    Assert.areEqual(2, objects.size());
    Assert.areEqual('Case', objects[0].objectApiName);
    Assert.areEqual('My Cases', objects[0].sectionLabel);
    Assert.areEqual('standard:case', objects[0].iconName);
    Assert.isTrue(objects[0].hasFacets);
    Assert.isFalse(objects[1].hasFacets);
    Assert.areEqual('Account', objects[1].objectApiName);
  }

  @IsTest
  static void lookupDetailsShowTheRelatedNameNeverTheId() {
    SearchConfig.ObjectConfig config = new SearchConfig.ObjectConfig();
    config.developerName = 'Contacts';
    config.objectApiName = 'Contact';
    config.titleField = 'LastName';
    config.detailFields = new List<String>{ 'AccountId' };
    SearchTarget target = new SchemaValidator().validate(config);
    String prefix = Contact.SObjectType.getDescribe(
        SObjectDescribeOptions.DEFERRED
      )
      .getKeyPrefix();
    Id accountId =
      Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
        .getKeyPrefix() + '000000000001';

    Contact withName = new Contact(
      Id = prefix + '000000000001',
      LastName = 'Lee',
      AccountId = accountId,
      Account = new Account(Id = accountId, Name = 'Acme')
    );
    // AccountId set but the related record not returned, as when sharing hides it.
    Contact hiddenAccount = new Contact(
      Id = prefix + '000000000002',
      LastName = 'Kim',
      AccountId = accountId
    );
    SearchResponseDto.ObjectGroup objectGroup = SearchResultMapper.toGroup(
      target,
      new List<BoostRuleEngine.ScoredRecord>{
        new BoostRuleEngine.ScoredRecord(withName, 0, 1),
        new BoostRuleEngine.ScoredRecord(hiddenAccount, 1, 1)
      },
      false
    );

    SearchResponseDto.Detail detail = objectGroup.results[0].details[0];
    Assert.areEqual('Acme', detail.value);
    Assert.areEqual(
      target.getLookupName(target.detailFields[0]).label,
      detail.label
    );
    Assert.isTrue(
      objectGroup.results[1].details.isEmpty(),
      'No name to show: the detail is left out rather than showing the ID'
    );
  }
}
