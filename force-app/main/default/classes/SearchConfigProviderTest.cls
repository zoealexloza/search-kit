@IsTest
private class SearchConfigProviderTest {
  @IsTest
  static void mapsDataCategoryFields() {
    Search_Config__mdt config = SearchTestFactory.config(
      SearchTestFactory.CONFIG_NAME,
      true,
      10
    );
    Search_Object__mdt articles = SearchTestFactory.searchObject(
      config,
      'Articles',
      'Knowledge__kav',
      'Title',
      null,
      10
    );
    articles.Data_Category_Group__c = 'Products';
    articles.Data_Category__c = 'Nimbus_Cloud';
    articles.Data_Category_Operator__c = 'at';
    SearchTestFactory.register(new List<SObject>{ config, articles });

    SearchConfig.ObjectConfig loaded = new SearchConfigProvider()
      .getActiveConfig(SearchTestFactory.CONFIG_NAME)
      .objects[0];

    Assert.areEqual('Products', loaded.dataCategoryGroup);
    Assert.areEqual('Nimbus_Cloud', loaded.dataCategory);
    Assert.areEqual('at', loaded.dataCategoryOperator);
  }

  @IsTest
  static void loadsActiveConfigWithChildrenInSortOrder() {
    Search_Config__mdt config = SearchTestFactory.config(
      SearchTestFactory.CONFIG_NAME,
      true,
      7
    );
    Search_Config__mdt otherConfig = SearchTestFactory.config(
      'Other_Config',
      true,
      10
    );
    Search_Object__mdt contacts = SearchTestFactory.searchObject(
      config,
      'Contacts',
      'Contact',
      'LastName',
      null,
      20
    );
    Search_Object__mdt accounts = SearchTestFactory.searchObject(
      config,
      'Accounts',
      'Account',
      'Name',
      new List<String>{ 'Industry', null, 'Phone' },
      10
    );
    Search_Object__mdt noOrder = SearchTestFactory.searchObject(
      config,
      'Cases',
      'Case',
      'Subject',
      null,
      null
    );
    Search_Object__mdt inactive = SearchTestFactory.searchObject(
      config,
      'Inactive',
      'Lead',
      'LastName',
      null,
      1
    );
    inactive.Is_Active__c = false;
    Search_Object__mdt otherObject = SearchTestFactory.searchObject(
      otherConfig,
      'Other',
      'Opportunity',
      'Name',
      null,
      1
    );
    SearchTestFactory.register(
      new List<SObject>{
        config,
        otherConfig,
        contacts,
        accounts,
        noOrder,
        inactive,
        otherObject,
        SearchTestFactory.filterRule(
          accounts,
          'Industry',
          'equals',
          'Technology'
        ),
        SearchTestFactory.boostRule(accounts, 'Rating', 'equals', 'Hot', 25),
        SearchTestFactory.boostRule(accounts, 'Phone', 'contains', '555', null),
        SearchTestFactory.facet(accounts, 'Type', null, 20),
        SearchTestFactory.facet(accounts, 'Industry', 'Sector', 10),
        SearchTestFactory.facet(inactive, 'LeadSource', null, 1),
        SearchTestFactory.facet(otherObject, 'StageName', null, 1)
      }
    );

    SearchConfig loaded = new SearchConfigProvider()
      .getActiveConfig(SearchTestFactory.CONFIG_NAME);

    Assert.areEqual(SearchTestFactory.CONFIG_NAME, loaded.developerName);
    Assert.areEqual(7, loaded.resultsPerObject);
    Assert.areEqual(
      3,
      loaded.objects.size(),
      'Inactive objects and other configs excluded'
    );
    Assert.areEqual('Accounts', loaded.objects[0].developerName);
    Assert.areEqual('Contacts', loaded.objects[1].developerName);
    Assert.areEqual(
      'Cases',
      loaded.objects[2].developerName,
      'Blank sort order sorts last'
    );

    SearchConfig.ObjectConfig accountConfig = loaded.objects[0];
    Assert.areEqual('Account', accountConfig.objectApiName);
    Assert.areEqual(
      new List<String>{ 'Industry', 'Phone' },
      accountConfig.detailFields,
      'Blank detail slots skipped'
    );
    Assert.areEqual(
      'Accounts',
      accountConfig.sectionLabel,
      'Falls back to the record label'
    );
    Assert.areEqual(1, accountConfig.filterRules.size());
    Assert.areEqual('Technology', accountConfig.filterRules[0].value);
    Assert.areEqual(2, accountConfig.boostRules.size());
    Assert.areEqual(25, accountConfig.boostRules[0].points);
    Assert.areEqual(
      0,
      accountConfig.boostRules[1].points,
      'Blank points count as zero'
    );
    Assert.areEqual(2, accountConfig.facets.size());
    Assert.areEqual(
      'Industry',
      accountConfig.facets[0].fieldApiName,
      'Facets sorted by sort order'
    );
    Assert.areEqual('Sector', accountConfig.facets[0].label);
    Assert.isTrue(loaded.objects[1].facets.isEmpty());
  }

  @IsTest
  static void configNameIsCaseInsensitiveAndTrimmed() {
    SearchTestFactory.register(
      new List<SObject>{
        SearchTestFactory.config(SearchTestFactory.CONFIG_NAME, true, null)
      }
    );

    SearchConfig loaded = new SearchConfigProvider()
      .getActiveConfig(
        '  ' + SearchTestFactory.CONFIG_NAME.toUpperCase() + ' '
      );

    Assert.areEqual(SearchTestFactory.CONFIG_NAME, loaded.developerName);
    Assert.areEqual(
      10,
      loaded.resultsPerObject,
      'Blank Results Per Object defaults to 10'
    );
    Assert.isTrue(loaded.objects.isEmpty());
  }

  @IsTest
  static void childrenMatchParentBy15CharacterId() {
    Search_Config__mdt config = SearchTestFactory.config(
      SearchTestFactory.CONFIG_NAME,
      true,
      null
    );
    Search_Object__mdt accounts = SearchTestFactory.searchObject(
      config,
      'Accounts',
      'Account',
      'Name',
      null,
      1
    );
    accounts.Search_Config__c = String.valueOf(config.Id).left(15);
    SearchTestFactory.register(new List<SObject>{ config, accounts });

    Assert.areEqual(
      1,
      new SearchConfigProvider()
        .getActiveConfig(SearchTestFactory.CONFIG_NAME)
        .objects.size()
    );
  }

  @IsTest
  static void unknownInactiveOrBlankConfigIsRejected() {
    SearchTestFactory.register(
      new List<SObject>{
        SearchTestFactory.config('Inactive_Config', false, 10)
      }
    );
    for (
      String name : new List<String>{
        'Inactive_Config',
        'Missing_Config',
        '',
        null,
        '\' OR Name != \''
      }
    ) {
      try {
        new SearchConfigProvider().getActiveConfig(name);
        Assert.fail('Expected SiteSearchException for ' + name);
      } catch (SiteSearchException e) {
        Assert.areEqual(
          System.Label.Search_Error_Config_Not_Found,
          e.getMessage()
        );
      }
    }
  }

  @IsTest
  static void readsCustomMetadataWhenNoTestRecordsAreRegistered() {
    // Uses the org's real getAll() data; a random name never exists.
    String name =
      'Missing_' + String.valueOf(Crypto.getRandomLong()).replace('-', '');
    try {
      new SearchConfigProvider().getActiveConfig(name);
      Assert.fail('Expected SiteSearchException');
    } catch (SiteSearchException e) {
      Assert.areEqual(
        System.Label.Search_Error_Config_Not_Found,
        e.getMessage()
      );
    }
  }

  @IsTest
  static void getAllIsUsedForChildrenWhenOnlyConfigIsRegistered() {
    SearchTestFactory.register(
      new List<SObject>{
        SearchTestFactory.config(SearchTestFactory.CONFIG_NAME, true, 5)
      }
    );
    SearchConfigProvider.objectRecords = null;
    SearchConfigProvider.facetRecords = null;
    SearchConfigProvider.filterRuleRecords = null;
    SearchConfigProvider.boostRuleRecords = null;

    // Real Search Objects belong to other configs (by Id), so none match the fake config.
    Assert.isTrue(
      new SearchConfigProvider()
        .getActiveConfig(SearchTestFactory.CONFIG_NAME)
        .objects.isEmpty()
    );
  }

  @IsTest
  static void resultsPerObjectIsClamped() {
    Assert.areEqual(10, SearchConfigProvider.clampResultsPerObject(null));
    Assert.areEqual(1, SearchConfigProvider.clampResultsPerObject(0));
    Assert.areEqual(1, SearchConfigProvider.clampResultsPerObject(-5));
    Assert.areEqual(25, SearchConfigProvider.clampResultsPerObject(25));
    Assert.areEqual(50, SearchConfigProvider.clampResultsPerObject(500));
  }

  @IsTest
  static void sortKeysOrderBlankLastThenByName() {
    Assert.areEqual(-1, SearchConfig.compareSortKeys(1, 'b', 2, 'a'));
    Assert.areEqual(1, SearchConfig.compareSortKeys(2, 'a', 1, 'b'));
    Assert.areEqual(1, SearchConfig.compareSortKeys(null, 'a', 1, 'b'));
    Assert.areEqual(-1, SearchConfig.compareSortKeys(1, 'b', null, 'a'));
    Assert.isTrue(SearchConfig.compareSortKeys(1, 'a', 1, 'b') < 0);
    Assert.isTrue(SearchConfig.compareSortKeys(null, null, null, 'b') < 0);
    Assert.areEqual(0, SearchConfig.compareSortKeys(null, null, null, null));
  }
}
