@IsTest
private class SearchServiceTest {
  /**
   * Registers a config searching Accounts (filter NumberOfEmployees > 0, boost Rating, facets
   * Industry and Type) and Contacts (no rules). Results Per Object: 3.
   */
  private static void registerConfig(String boostRating) {
    Search_Config__mdt config = SearchTestFactory.config(
      SearchTestFactory.CONFIG_NAME,
      true,
      3
    );
    Search_Object__mdt accounts = SearchTestFactory.searchObject(
      config,
      'Accounts',
      'Account',
      'Name',
      new List<String>{ 'Industry', 'NumberOfEmployees' },
      10
    );
    Search_Object__mdt contacts = SearchTestFactory.searchObject(
      config,
      'Contacts',
      'Contact',
      'LastName',
      new List<String>{ 'Email' },
      20
    );
    Search_Object__mdt broken = SearchTestFactory.searchObject(
      config,
      'Broken',
      'Not_A_Real_Object__c',
      'Name',
      null,
      30
    );
    SearchTestFactory.register(
      new List<SObject>{
        config,
        accounts,
        contacts,
        broken,
        SearchTestFactory.filterRule(
          accounts,
          'NumberOfEmployees',
          'greater_than',
          '0'
        ),
        SearchTestFactory.boostRule(
          accounts,
          'Rating',
          'equals',
          boostRating,
          50
        ),
        SearchTestFactory.facet(accounts, 'Industry', null, 10),
        SearchTestFactory.facet(accounts, 'Type', null, 20)
      }
    );
  }

  private static List<Id> ids(List<SObject> records) {
    return new List<Id>(new Map<Id, SObject>(records).keySet());
  }

  private static List<String> titles(
    SearchResponseDto.ObjectGroup objectGroup
  ) {
    List<String> titles = new List<String>();
    for (SearchResponseDto.Result result : objectGroup.results) {
      titles.add(result.title);
    }
    return titles;
  }

  // ---- SOSL path ----

  @IsTest
  static void termSearchReturnsBoostedGroupsInConfigOrder() {
    String hot = SearchTestFactory.picklistValues(Account.Rating, 1)[0];
    registerConfig(hot);
    List<Account> accounts = new List<Account>{
      new Account(Name = 'Widget plain one', NumberOfEmployees = 10),
      new Account(Name = 'Widget plain two', NumberOfEmployees = 10),
      new Account(Name = 'Widget boosted', NumberOfEmployees = 10, Rating = hot)
    };
    insert accounts;
    Contact person = new Contact(
      LastName = 'Widgetson',
      Email = 'widget@example.com'
    );
    insert person;
    List<Id> fixed = ids(accounts);
    fixed.add(person.Id);
    Test.setFixedSearchResults(fixed);

    Test.startTest();
    SearchResponseDto response = new SearchService()
      .search(SearchTestFactory.request('  widget  '));
    Test.stopTest();

    Assert.areEqual(SearchResponseDto.MODE_SEARCH, response.mode);
    Assert.areEqual('widget', response.searchTerm);
    Assert.areEqual(
      2,
      response.groups.size(),
      'Broken object skipped, others still searched'
    );
    SearchResponseDto.ObjectGroup accountGroup = response.groups[0];
    Assert.areEqual('Account', accountGroup.objectApiName);
    Assert.areEqual(3, accountGroup.totalShown);
    Assert.isFalse(accountGroup.hasMore);
    Assert.areEqual(
      'Widget boosted',
      accountGroup.results[0].title,
      'Boost rule moves the matching record to the top'
    );
    Assert.isTrue(
      accountGroup.results[0].score > accountGroup.results[1].score
    );
    Assert.areEqual('Contact', response.groups[1].objectApiName);
    Assert.areEqual('Widgetson', response.groups[1].results[0].title);
    Assert.areEqual(
      'widget@example.com',
      response.groups[1].results[0].details[0].value
    );
    Assert.areEqual(
      2,
      response.facets.size(),
      'Facets are returned with results'
    );
    Assert.areEqual(
      'Accounts',
      response.facets[0].sectionLabel,
      'Facets carry their object\'s section label'
    );
  }

  @IsTest
  static void filterRulesApplyToTermSearch() {
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);
    Account visible = new Account(
      Name = 'Gadget visible',
      NumberOfEmployees = 5
    );
    Account filteredOut = new Account(
      Name = 'Gadget filtered',
      NumberOfEmployees = 0
    );
    insert new List<Account>{ visible, filteredOut };
    Test.setFixedSearchResults(new List<Id>{ visible.Id, filteredOut.Id });

    SearchResponseDto response = new SearchService()
      .search(SearchTestFactory.request('gadget'));

    Assert.areEqual(1, response.groups.size());
    Assert.areEqual(
      new List<String>{ 'Gadget visible' },
      titles(response.groups[0]),
      'Filter NumberOfEmployees > 0 excludes the other record'
    );
  }

  @IsTest
  static void facetSelectionsNarrowTermSearch() {
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      2
    );
    Account match = new Account(
      Name = 'Sprocket match',
      NumberOfEmployees = 5,
      Industry = industries[0]
    );
    Account other = new Account(
      Name = 'Sprocket other',
      NumberOfEmployees = 5,
      Industry = industries[1]
    );
    insert new List<Account>{ match, other };
    Test.setFixedSearchResults(new List<Id>{ match.Id, other.Id });
    SearchRequestDto request = SearchTestFactory.request('sprocket');
    request.selectedFacets.add(
      SearchTestFactory.selection(
        'Account',
        'Industry',
        new List<String>{ industries[0] }
      )
    );

    SearchResponseDto response = new SearchService().search(request);

    Assert.areEqual(
      new List<String>{ 'Sprocket match' },
      titles(response.groups[0])
    );
    Assert.isTrue(response.facets[0].values.size() > 0);
  }

  @IsTest
  static void loadMoreReportsHasMoreAndHonoursRequestedLimit() {
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);
    List<Account> accounts = new List<Account>();
    for (Integer i = 0; i < 5; i++) {
      accounts.add(new Account(Name = 'Bolt ' + i, NumberOfEmployees = 1));
    }
    insert accounts;
    Test.setFixedSearchResults(ids(accounts));

    SearchResponseDto firstPage = new SearchService()
      .search(SearchTestFactory.request('bolt'));
    SearchRequestDto more = SearchTestFactory.request('bolt');
    more.limitPerObject = 6;
    SearchResponseDto secondPage = new SearchService().search(more);

    Assert.areEqual(
      3,
      firstPage.groups[0].totalShown,
      'Config default of 3 per object'
    );
    Assert.isTrue(firstPage.groups[0].hasMore);
    Assert.areEqual(5, secondPage.groups[0].totalShown);
    Assert.isFalse(secondPage.groups[0].hasMore);
  }

  @IsTest
  static void boostedRecordBelowFirstPageReachesIt() {
    String hot = SearchTestFactory.picklistValues(Account.Rating, 1)[0];
    registerConfig(hot);
    // Page size 3, so the pool is 9 rows + 1. The boosted record is 8th in SOSL order: with a
    // pool of only limit + 1 rows it would never be fetched.
    List<Account> accounts = new List<Account>();
    for (Integer i = 0; i < 10; i++) {
      accounts.add(
        new Account(
          Name = 'Rivet ' + i,
          NumberOfEmployees = 1,
          Rating = i == 7 ? hot : null
        )
      );
    }
    insert accounts;
    List<Id> fixed = new List<Id>();
    for (Account account : accounts) {
      fixed.add(account.Id);
    }
    Test.setFixedSearchResults(fixed);

    SearchResponseDto response = new SearchService()
      .search(SearchTestFactory.request('rivet'));

    SearchResponseDto.ObjectGroup accountGroup = response.groups[0];
    Assert.areEqual(3, accountGroup.totalShown, 'Still one page shown');
    Assert.isTrue(accountGroup.hasMore);
    Assert.areEqual(
      'Rivet 7',
      accountGroup.results[0].title,
      'Boosted record from below the first page ranks first'
    );
  }

  @IsTest
  static void candidateRowLimitScalesAndRespectsSoslTotal() {
    // limit, object count, expected rows per object
    List<List<Integer>> cases = new List<List<Integer>>{
      new List<Integer>{ 3, 2, 10 }, // 3 x 3 + 1
      new List<Integer>{ 10, 1, 31 },
      new List<Integer>{ 100, 1, 201 }, // pool capped at 200
      new List<Integer>{ 200, 1, 201 }, // pool never below the limit
      new List<Integer>{ 50, 20, 100 }, // 2,000 / 20 objects
      new List<Integer>{ 200, 20, 201 }, // never below limit + 1
      new List<Integer>{ 10, 0, 31 } // no division by zero
    };
    for (List<Integer> testCase : cases) {
      Assert.areEqual(
        testCase[2],
        SearchService.candidateRowLimit(testCase[0], testCase[1]),
        'limit ' + testCase[0] + ', objects ' + testCase[1]
      );
    }
  }

  // ---- SOQL browse path ----

  @IsTest
  static void facetsWithoutTermBrowseWithSoql() {
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      2
    );
    insert new List<Account>{
      new Account(
        Name = 'B match',
        NumberOfEmployees = 5,
        Industry = industries[0]
      ),
      new Account(
        Name = 'A match',
        NumberOfEmployees = 5,
        Industry = industries[0]
      ),
      new Account(
        Name = 'Other industry',
        NumberOfEmployees = 5,
        Industry = industries[1]
      ),
      new Account(
        Name = 'Filtered out',
        NumberOfEmployees = 0,
        Industry = industries[0]
      )
    };
    insert new Contact(LastName = 'Not browsed');
    SearchRequestDto request = SearchTestFactory.request('a'); // too short for SOSL
    request.selectedFacets.add(
      SearchTestFactory.selection(
        'account',
        'INDUSTRY',
        new List<String>{ industries[0].toLowerCase() }
      )
    );

    SearchResponseDto response = new SearchService().search(request);

    Assert.areEqual(SearchResponseDto.MODE_BROWSE, response.mode);
    Assert.areEqual(
      1,
      response.groups.size(),
      'Only objects with a facet selection are browsed'
    );
    Assert.areEqual(
      new List<String>{ 'A match', 'B match' },
      titles(response.groups[0]),
      'Sorted by title, filter still applied'
    );
    Boolean selectedShown = false;
    for (SearchResponseDto.FacetValue value : response.facets[0].values) {
      selectedShown =
        selectedShown || (value.selected && value.value == industries[0]);
    }
    Assert.isTrue(selectedShown, 'Selected facet value is marked');
  }

  @IsTest
  static void noTermAndNoFacetsRunsNoQuery() {
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);

    Test.startTest();
    SearchResponseDto response = new SearchService()
      .search(SearchTestFactory.request(null));
    Integer queries = Limits.getQueries();
    Test.stopTest();

    Assert.areEqual(SearchResponseDto.MODE_NONE, response.mode);
    Assert.isTrue(response.groups.isEmpty());
    Assert.areEqual(
      2,
      response.facets.size(),
      'Facets still returned so the UI can offer browsing'
    );
    Assert.areEqual(0, queries);
  }

  @IsTest
  static void invalidFacetSelectionDoesNotTriggerBrowse() {
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);
    SearchRequestDto request = SearchTestFactory.request('');
    request.selectedFacets.add(
      SearchTestFactory.selection(
        'Account',
        'Industry',
        new List<String>{ '\' OR Name != \'' }
      )
    );
    request.selectedFacets.add(
      SearchTestFactory.selection('Account', 'Name', new List<String>{ 'x' })
    );

    SearchResponseDto response = new SearchService().search(request);

    Assert.areEqual(SearchResponseDto.MODE_NONE, response.mode);
  }

  // ---- hostile input ----

  @IsTest
  static void injectionStyleTermsAreSafe() {
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);
    Account record = new Account(Name = 'Anchor', NumberOfEmployees = 1);
    insert record;
    Test.setFixedSearchResults(new List<Id>{ record.Id });
    List<String> terms = new List<String>{
      '\'',
      '\\',
      '\\\'',
      'x\' IN ALL FIELDS RETURNING User(Id, Username)',
      'anchor} RETURNING User(Username) FIND {x',
      '"anchor" AND NOT (x OR y) * ? ~ ^ : + - ! & |',
      'anchor\\\' LIMIT 1',
      'a'.repeat(100000)
    };
    for (String term : terms) {
      SearchResponseDto response = new SearchService()
        .search(SearchTestFactory.request(term));
      Assert.isFalse(
        response.searchTerm.contains('\''),
        'No quote survives: ' + term.left(40)
      );
      Assert.isFalse(
        response.searchTerm.contains('\\'),
        'No backslash survives: ' + term.left(40)
      );
      Assert.isTrue(
        response.searchTerm.length() <= SearchQueryBuilder.MAX_TERM_LENGTH
      );
      for (SearchResponseDto.ObjectGroup objectGroup : response.groups) {
        Assert.areNotEqual(
          'User',
          objectGroup.objectApiName,
          'Only configured objects are returned'
        );
      }
    }
  }

  @IsTest
  static void termThatSanitizesToNothingRunsNoSearch() {
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);

    SearchResponseDto response = new SearchService()
      .search(SearchTestFactory.request('\'"*?-'));

    Assert.areEqual(SearchResponseDto.MODE_NONE, response.mode);
    Assert.areEqual('', response.searchTerm);
  }

  // ---- configuration and access problems ----

  @IsTest
  static void unknownConfigIsRejected() {
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);
    SearchRequestDto request = SearchTestFactory.request('widget');
    request.configName = 'Something_Else';
    try {
      new SearchService().search(request);
      Assert.fail('Expected SiteSearchException');
    } catch (SiteSearchException e) {
      Assert.areEqual(
        System.Label.Search_Error_Config_Not_Found,
        e.getMessage()
      );
    }
  }

  @IsTest
  static void missingRequestIsRejected() {
    try {
      new SearchService().search(null);
      Assert.fail('Expected SiteSearchException');
    } catch (SiteSearchException e) {
      Assert.areEqual(
        System.Label.Search_Error_Invalid_Request,
        e.getMessage()
      );
    }
  }

  @IsTest
  static void configWithNoUsableObjectsReturnsEmptyResponse() {
    Search_Config__mdt config = SearchTestFactory.config(
      SearchTestFactory.CONFIG_NAME,
      true,
      10
    );
    SearchTestFactory.register(
      new List<SObject>{
        config,
        SearchTestFactory.searchObject(
          config,
          'Broken',
          'Nope__c',
          'Name',
          null,
          1
        )
      }
    );

    SearchResponseDto response = new SearchService()
      .search(SearchTestFactory.request('anything'));

    Assert.areEqual(SearchResponseDto.MODE_NONE, response.mode);
    Assert.isTrue(response.groups.isEmpty());
    Assert.isTrue(response.facets.isEmpty());
  }

  @IsTest
  static void guestLikeUserWithoutObjectAccessGetsNoResults() {
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);
    Account record = new Account(Name = 'Secret widget', NumberOfEmployees = 1);
    insert record;
    Test.setFixedSearchResults(new List<Id>{ record.Id });
    User guestLike = SearchTestFactory.minimumAccessUser(false);

    System.runAs(guestLike) {
      SearchResponseDto response = new SearchService()
        .search(SearchTestFactory.request('widget'));
      Assert.isTrue(
        response.groups.isEmpty(),
        'No access to Account or Contact: nothing searched'
      );
      Assert.isTrue(response.facets.isEmpty());
    }
  }

  @IsTest
  static void userWithoutFieldAccessStillSearchesVisibleFields() {
    // Account Read but no field permissions: Industry, Type, Rating and NumberOfEmployees
    // are hidden, so the filter on NumberOfEmployees makes the object fail closed.
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);
    User restricted = SearchTestFactory.minimumAccessUser(true);

    System.runAs(restricted) {
      SearchResponseDto response = new SearchService()
        .search(SearchTestFactory.request('widget'));
      Assert.isTrue(response.groups.isEmpty());
      Assert.isTrue(
        response.facets.isEmpty(),
        'Facets on hidden fields are not offered'
      );
    }
  }

  // ---- object scope (object tabs, M8.5) ----

  private static List<String> objectNames(SearchResponseDto response) {
    List<String> names = new List<String>();
    for (SearchResponseDto.SearchableObject searchable : response.objects) {
      names.add(searchable.objectApiName);
    }
    return names;
  }

  /** Inserts one Account and one Contact that both match "widget", as fixed SOSL results. */
  private static void insertWidgets() {
    Account company = new Account(Name = 'Widget Co', NumberOfEmployees = 5);
    Contact person = new Contact(LastName = 'Widgetson');
    insert company;
    insert person;
    Test.setFixedSearchResults(new List<Id>{ company.Id, person.Id });
  }

  @IsTest
  static void scopedSearchQueriesOnlyTheRequestedObject() {
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);
    insertWidgets();
    SearchRequestDto request = SearchTestFactory.request('widget');
    request.objectApiNames = new List<String>{ 'CONTACT' };

    SearchResponseDto response = new SearchService().search(request);

    Assert.areEqual(1, response.groups.size());
    Assert.areEqual('Contact', response.groups[0].objectApiName);
    Assert.isTrue(
      response.facets.isEmpty(),
      'Only the scoped object\'s facets are returned (Contacts has none)'
    );
    Assert.areEqual(
      new List<String>{ 'Account', 'Contact' },
      objectNames(response),
      'Every searchable object is listed for the tabs, whatever the scope'
    );
    Assert.areEqual('Accounts', response.objects[0].sectionLabel);
  }

  @IsTest
  static void scopedSearchReturnsOnlyThatObjectsFacets() {
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);
    insertWidgets();
    SearchRequestDto request = SearchTestFactory.request('widget');
    request.objectApiNames = new List<String>{ 'Account' };

    SearchResponseDto response = new SearchService().search(request);

    Assert.areEqual(1, response.groups.size());
    Assert.areEqual('Account', response.groups[0].objectApiName);
    Assert.areEqual(2, response.facets.size(), 'Industry and Type');
    Assert.areEqual(2, response.objects.size());
  }

  @IsTest
  static void unknownOrUnsafeScopeSearchesEverything() {
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);
    insertWidgets();
    SearchRequestDto request = SearchTestFactory.request('widget');
    request.objectApiNames = new List<String>{
      null,
      'Not_A_Real_Object__c', // configured but invalid
      'User', // real, not in the config
      'Account) RETURNING User(Id',
      ''
    };

    SearchResponseDto response = new SearchService().search(request);

    Assert.areEqual(
      2,
      response.groups.size(),
      'No valid name in the scope, so every object is searched'
    );
  }

  @IsTest
  static void facetSelectionsOutsideTheScopeAreIgnored() {
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);
    SearchRequestDto request = SearchTestFactory.request('');
    request.objectApiNames = new List<String>{ 'Contact' };
    request.selectedFacets.add(
      SearchTestFactory.selection(
        'Account',
        'Industry',
        SearchTestFactory.picklistValues(Account.Industry, 1)
      )
    );

    SearchResponseDto response = new SearchService().search(request);

    Assert.areEqual(
      SearchResponseDto.MODE_NONE,
      response.mode,
      'An Account selection does not trigger a browse on the Contacts tab'
    );
    Assert.isTrue(response.groups.isEmpty());
  }

  @IsTest
  static void scopeCannotAddAnObjectTheUserCannotRead() {
    registerConfig(SearchTestFactory.picklistValues(Account.Rating, 1)[0]);
    Account record = new Account(Name = 'Secret widget', NumberOfEmployees = 1);
    insert record;
    Test.setFixedSearchResults(new List<Id>{ record.Id });
    User guestLike = SearchTestFactory.minimumAccessUser(false);

    System.runAs(guestLike) {
      SearchRequestDto request = SearchTestFactory.request('widget');
      request.objectApiNames = new List<String>{ 'Account' };
      SearchResponseDto response = new SearchService().search(request);
      Assert.isTrue(response.groups.isEmpty());
      Assert.isTrue(
        response.objects.isEmpty(),
        'No tabs for objects the user cannot search'
      );
    }
  }

  @IsTest
  static void scopeTargetsMatchesIgnoringCaseAndCapsTheList() {
    SchemaValidator validator = new SchemaValidator();
    List<SearchTarget> targets = new List<SearchTarget>();
    for (String name : new List<String>{ 'Account', 'Contact', 'Case' }) {
      SearchConfig.ObjectConfig objectConfig = new SearchConfig.ObjectConfig();
      objectConfig.developerName = name;
      objectConfig.objectApiName = name;
      objectConfig.titleField = 'Id';
      targets.add(validator.validate(objectConfig));
    }

    Assert.areEqual(3, SearchService.scopeTargets(targets, null).size());
    Assert.areEqual(
      3,
      SearchService.scopeTargets(targets, new List<String>()).size()
    );
    List<SearchTarget> scoped = SearchService.scopeTargets(
      targets,
      new List<String>{ 'case', 'ACCOUNT' }
    );
    Assert.areEqual(2, scoped.size());
    Assert.areEqual('Account', scoped[0].objectApiName, 'Config order kept');
    Assert.areEqual('Case', scoped[1].objectApiName);

    List<String> padded = new List<String>();
    for (Integer i = 0; i < SearchService.MAX_SCOPE_NAMES; i++) {
      padded.add('Nope' + i);
    }
    padded.add('Contact');
    Assert.areEqual(
      3,
      SearchService.scopeTargets(targets, padded).size(),
      'Names past MAX_SCOPE_NAMES are not read'
    );
  }

  @IsTest
  static void resolveLimitUsesConfigDefaultAndCaps() {
    Assert.areEqual(10, SearchService.resolveLimit(null, 10));
    Assert.areEqual(10, SearchService.resolveLimit(0, 10));
    Assert.areEqual(10, SearchService.resolveLimit(-3, 10));
    Assert.areEqual(25, SearchService.resolveLimit(25, 10));
    Assert.areEqual(
      SearchService.MAX_LIMIT_PER_OBJECT,
      SearchService.resolveLimit(100000, 10)
    );
  }
}
