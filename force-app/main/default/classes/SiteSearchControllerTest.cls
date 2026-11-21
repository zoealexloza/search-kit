@IsTest
private class SiteSearchControllerTest {
  @IsTest
  static void searchReturnsResults() {
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
          'Accounts',
          'Account',
          'Name',
          null,
          1
        )
      }
    );
    Account record = new Account(Name = 'Controller test');
    insert record;
    Test.setFixedSearchResults(new List<Id>{ record.Id });

    SearchResponseDto response = SiteSearchController.search(
      SearchTestFactory.request('controller')
    );

    Assert.areEqual(1, response.groups.size());
    Assert.areEqual(record.Id, response.groups[0].results[0].recordId);
  }

  @IsTest
  static void expectedErrorsKeepTheirLabelMessage() {
    SearchTestFactory.register(new List<SObject>());
    try {
      SiteSearchController.search(SearchTestFactory.request('anything'));
      Assert.fail('Expected AuraHandledException');
    } catch (AuraHandledException e) {
      Assert.areEqual(
        System.Label.Search_Error_Config_Not_Found,
        e.getMessage()
      );
    }
  }

  @IsTest
  static void unexpectedErrorsBecomeGenericMessage() {
    SiteSearchController.service = (SearchService) Test.createStub(
      SearchService.class,
      new FailingService()
    );
    try {
      SiteSearchController.search(SearchTestFactory.request('anything'));
      Assert.fail('Expected AuraHandledException');
    } catch (AuraHandledException e) {
      Assert.areEqual(
        System.Label.Search_Error_Generic,
        e.getMessage(),
        'Internal details are not exposed'
      );
    }
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
      throw new QueryException(
        'Internal detail: SELECT Secret__c FROM Hidden__c'
      );
    }
  }
}
