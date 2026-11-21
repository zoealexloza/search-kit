@IsTest
private class SiteSearchActionTest {
  /**
   * Registers a config searching Accounts and Contacts, with Allow_Agent_Access__c as given.
   * Results Per Object: 3 (the action asks for its own number of results).
   */
  private static void registerConfig(Boolean allowAgentAccess) {
    Search_Config__mdt config = SearchTestFactory.config(
      SearchTestFactory.CONFIG_NAME,
      true,
      3
    );
    config.Allow_Agent_Access__c = allowAgentAccess;
    Search_Object__mdt accounts = SearchTestFactory.searchObject(
      config,
      'Accounts',
      'Account',
      'Name',
      new List<String>{ 'NumberOfEmployees' },
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
    SearchTestFactory.register(new List<SObject>{ config, accounts, contacts });
  }

  private static SiteSearchAction.Request request(String term) {
    SiteSearchAction.Request request = new SiteSearchAction.Request();
    request.configName = SearchTestFactory.CONFIG_NAME;
    request.searchTerm = term;
    return request;
  }

  private static SiteSearchAction.Response searchOne(
    SiteSearchAction.Request request
  ) {
    List<SiteSearchAction.Response> responses = SiteSearchAction.search(
      new List<SiteSearchAction.Request>{ request }
    );
    Assert.areEqual(1, responses.size());
    return responses[0];
  }

  /** Three accounts and two contacts matching "widget", as fixed SOSL results in that order. */
  private static void insertWidgets() {
    List<Account> accounts = new List<Account>{
      new Account(Name = 'Widget A1', NumberOfEmployees = 10),
      new Account(Name = 'Widget A2', NumberOfEmployees = 20),
      new Account(Name = 'Widget A3', NumberOfEmployees = 30)
    };
    List<Contact> contacts = new List<Contact>{
      new Contact(LastName = 'Widget C1'),
      new Contact(LastName = 'Widget C2')
    };
    insert accounts;
    insert contacts;
    List<Id> fixed = new List<Id>();
    for (SObject record : accounts) {
      fixed.add(record.Id);
    }
    for (SObject record : contacts) {
      fixed.add(record.Id);
    }
    Test.setFixedSearchResults(fixed);
  }

  private static List<String> titles(SiteSearchAction.Response response) {
    List<String> titles = new List<String>();
    for (SiteSearchAction.Result result : response.results) {
      titles.add(result.title);
    }
    return titles;
  }

  @IsTest
  static void returnsResultsMixedByRankWithSummary() {
    registerConfig(true);
    insertWidgets();

    SiteSearchAction.Request req = request('widget');
    req.maxResults = 4;
    SiteSearchAction.Response response = searchOne(req);

    Assert.isNull(response.errorMessage);
    Assert.areEqual(
      new List<String>{ 'Widget A1', 'Widget C1', 'Widget A2', 'Widget C2' },
      titles(response),
      'Each object\'s best first, then each object\'s second best'
    );
    SiteSearchAction.Result first = response.results[0];
    Assert.areEqual('Account', first.objectApiName);
    Assert.areEqual('Accounts', first.sectionLabel);
    Assert.isNotNull(first.recordId);
    Assert.areEqual(
      Account.NumberOfEmployees.getDescribe().getLabel() + ': 10',
      first.details
    );
    Assert.isTrue(
      response.summary.startsWith(
        String.format(
          System.Label.Search_Agent_Summary,
          new List<Object>{ 4, 'widget' }
        )
      ),
      response.summary
    );
    Assert.isTrue(
      response.summary.contains('\n1. Widget A1 (Accounts) - '),
      response.summary
    );
    Assert.isTrue(
      response.summary.contains('\n2. Widget C1 (Contacts)\n'),
      'No dash without details: ' + response.summary
    );
  }

  @IsTest
  static void defaultsToFiveResultsAndCapsAtTen() {
    Assert.areEqual(
      SiteSearchAction.DEFAULT_MAX_RESULTS,
      SiteSearchAction.resolveMaxResults(null)
    );
    Assert.areEqual(
      SiteSearchAction.DEFAULT_MAX_RESULTS,
      SiteSearchAction.resolveMaxResults(0)
    );
    Assert.areEqual(
      SiteSearchAction.DEFAULT_MAX_RESULTS,
      SiteSearchAction.resolveMaxResults(-3)
    );
    Assert.areEqual(3, SiteSearchAction.resolveMaxResults(3));
    Assert.areEqual(
      SiteSearchAction.MAX_RESULTS,
      SiteSearchAction.resolveMaxResults(500)
    );

    registerConfig(true);
    insertWidgets();
    Assert.areEqual(
      5,
      searchOne(request('widget')).results.size(),
      'Default 5 of the 5 matches'
    );
  }

  @IsTest
  static void configWithoutAgentAccessIsRefused() {
    registerConfig(false);
    insertWidgets();

    SiteSearchAction.Response response = searchOne(request('widget'));

    Assert.areEqual(
      System.Label.Search_Agent_Not_Allowed,
      response.errorMessage
    );
    Assert.areEqual(response.errorMessage, response.summary);
    Assert.isTrue(response.results.isEmpty());
  }

  @IsTest
  static void unknownOrMissingConfigReturnsTheLabelMessage() {
    registerConfig(true);
    SiteSearchAction.Request unknown = request('widget');
    unknown.configName = 'No_Such_Config';
    SiteSearchAction.Request blank = request('widget');
    blank.configName = null;

    List<SiteSearchAction.Response> responses = SiteSearchAction.search(
      new List<SiteSearchAction.Request>{ unknown, blank, null }
    );

    Assert.areEqual(
      System.Label.Search_Error_Config_Not_Found,
      responses[0].errorMessage
    );
    Assert.areEqual(
      System.Label.Search_Error_Config_Not_Found,
      responses[1].errorMessage
    );
    Assert.areEqual(
      System.Label.Search_Error_Invalid_Request,
      responses[2].errorMessage
    );
    Assert.isTrue(SiteSearchAction.search(null).isEmpty());
  }

  @IsTest
  static void noResultsSaysSo() {
    registerConfig(true);
    Test.setFixedSearchResults(new List<Id>());

    SiteSearchAction.Response response = searchOne(request('nothing here'));

    Assert.isNull(response.errorMessage);
    Assert.isTrue(response.results.isEmpty());
    Assert.areEqual(
      String.format(
        System.Label.Search_Agent_No_Results,
        new List<Object>{ 'nothing here' }
      ),
      response.summary
    );
  }

  @IsTest
  static void injectionStyleTermsAreSafe() {
    registerConfig(true);
    insertWidgets();
    for (
      String term : new List<String>{
        'widget\' RETURNING User(Id)',
        'widget\\\' OR Name != \'',
        'widget} FIND {x',
        '*',
        '',
        null,
        'x'.repeat(5000)
      }
    ) {
      SiteSearchAction.Response response = searchOne(request(term));
      Assert.isNull(response.errorMessage, 'Term: ' + term);
      for (SiteSearchAction.Result result : response.results) {
        Assert.isTrue(
          result.objectApiName == 'Account' ||
            result.objectApiName == 'Contact',
          'Only configured objects: ' + result.objectApiName
        );
      }
    }
  }

  @IsTest
  static void stopsWhenTheTransactionIsLowOnSoslQueries() {
    registerConfig(true);
    insertWidgets();
    Test.startTest();
    // Other code in the transaction has used all but SOSL_PER_REQUEST queries.
    Integer toUse =
      Limits.getLimitSoslQueries() - SiteSearchAction.SOSL_PER_REQUEST;
    for (Integer i = 0; i < toUse; i++) {
      Search.query(
        'FIND \'unused\' IN ALL FIELDS RETURNING Account(Id)',
        AccessLevel.USER_MODE
      );
    }
    List<SiteSearchAction.Response> responses = SiteSearchAction.search(
      new List<SiteSearchAction.Request>{ request('widget'), request('widget') }
    );
    Integer soslQueries = Limits.getSoslQueries();
    Test.stopTest();

    Assert.isNull(responses[0].errorMessage, 'Enough budget for the first');
    Assert.areEqual(
      System.Label.Search_Agent_Too_Many,
      responses[1].errorMessage,
      'Fewer than SOSL_PER_REQUEST left for the second'
    );
    Assert.isTrue(soslQueries < Limits.getLimitSoslQueries());
  }

  @IsTest
  static void bulkRequestsAreCappedWithinTheSoslLimit() {
    registerConfig(true);
    insertWidgets();
    List<SiteSearchAction.Request> requests = new List<SiteSearchAction.Request>();
    for (Integer i = 0; i < 200; i++) {
      requests.add(request('widget'));
    }

    Test.startTest();
    List<SiteSearchAction.Response> responses = SiteSearchAction.search(
      requests
    );
    Integer soslQueries = Limits.getSoslQueries();
    Test.stopTest();

    Assert.areEqual(200, responses.size(), 'One response per request');
    Assert.areEqual(SiteSearchAction.MAX_REQUESTS, soslQueries);
    for (Integer i = 0; i < responses.size(); i++) {
      if (i < SiteSearchAction.MAX_REQUESTS) {
        Assert.isNull(responses[i].errorMessage, 'Request ' + i);
        Assert.isFalse(responses[i].results.isEmpty(), 'Request ' + i);
      } else {
        Assert.areEqual(
          System.Label.Search_Agent_Too_Many,
          responses[i].errorMessage,
          'Request ' + i
        );
      }
    }
  }

  @IsTest
  static void minimumAccessAgentUserGetsNoRecords() {
    // Stands in for an agent user without object access: it can't see the records.
    registerConfig(true);
    insertWidgets();
    User agentLike = SearchTestFactory.minimumAccessUser(false);

    System.runAs(agentLike) {
      SiteSearchAction.Response response = searchOne(request('widget'));
      Assert.isNull(response.errorMessage);
      Assert.isTrue(response.results.isEmpty());
    }
  }

  @IsTest
  static void unexpectedErrorsBecomeGenericMessage() {
    registerConfig(true);
    SiteSearchAction.service = (SearchService) Test.createStub(
      SearchService.class,
      new FailingService()
    );

    SiteSearchAction.Response response = searchOne(request('widget'));

    Assert.areEqual(
      System.Label.Search_Error_Generic,
      response.errorMessage,
      'Internal details are not exposed'
    );
  }

  /** Stub that fails the way an unexpected platform error would. */
  private class FailingService implements System.StubProvider {
    public Object handleMethodCall(
      Object stubbedObject,
      String stubbedMethodName,
      Type returnType,
      List<Type> listOfParamTypes,
      List<String> listOfParamNames,
      List<Object> listOfArgs
    ) {
      throw new QueryException('Internal detail: SELECT Secret__c FROM X__c');
    }
  }
}
