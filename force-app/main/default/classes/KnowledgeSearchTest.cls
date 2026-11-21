/**
 * Knowledge article objects in the validator, query builder and service. Knowledge isn't on in
 * every org, so everything refers to Knowledge__kav by name and each test returns early if it
 * can't be described (the packaging scratch definition turns Knowledge on, so the tests run
 * there).
 *
 * Published articles can only be made with KbManagement, which would make Knowledge a package
 * dependency, so the published path is checked through the generated query text, and drafts
 * through Test.setFixedSearchResults (which still applies the RETURNING WHERE filters).
 */
@IsTest
private class KnowledgeSearchTest {
  private static final String ARTICLE_OBJECT = 'Knowledge__kav';

  private static Boolean knowledgeAvailable() {
    return new SchemaValidator().describeObject(ARTICLE_OBJECT) != null;
  }

  private static SearchConfig.ObjectConfig articleConfig() {
    SearchConfig.ObjectConfig objectConfig = new SearchConfig.ObjectConfig();
    objectConfig.developerName = 'Articles';
    objectConfig.objectApiName = ARTICLE_OBJECT;
    objectConfig.titleField = 'Title';
    return objectConfig;
  }

  private static SearchTarget accountTarget() {
    SearchConfig.ObjectConfig objectConfig = new SearchConfig.ObjectConfig();
    objectConfig.developerName = 'Accounts';
    objectConfig.objectApiName = 'Account';
    objectConfig.titleField = 'Name';
    return new SchemaValidator().validate(objectConfig);
  }

  private static SearchTarget articleTargetWithCategory() {
    KnowledgeSupport.visibleCategoriesOverride = new Map<String, Set<String>>{
      'Products' => new Set<String>{ 'Nimbus_Cloud' }
    };
    SearchConfig.ObjectConfig objectConfig = articleConfig();
    objectConfig.dataCategoryGroup = 'Products';
    objectConfig.dataCategory = 'Nimbus_Cloud';
    objectConfig.dataCategoryOperator = KnowledgeSupport.OP_AT_OR_BELOW;
    return new SchemaValidator().validate(objectConfig);
  }

  /**
   * Registers config CONFIG_NAME: articles first (no category), then accounts.
   * @return the articles' Search Object record, for tests that change it
   */
  private static Search_Object__mdt registerConfig() {
    Search_Config__mdt config = SearchTestFactory.config(
      SearchTestFactory.CONFIG_NAME,
      true,
      10
    );
    Search_Object__mdt articles = SearchTestFactory.searchObject(
      config,
      'Articles',
      ARTICLE_OBJECT,
      'Title',
      null,
      10
    );
    Search_Object__mdt accounts = SearchTestFactory.searchObject(
      config,
      'Accounts',
      'Account',
      'Name',
      null,
      20
    );
    SearchTestFactory.register(
      new List<SObject>{
        config,
        articles,
        accounts,
        SearchTestFactory.facet(articles, 'Language', null, 10)
      }
    );
    return articles;
  }

  /**
   * A System Administrator with the Knowledge User permission, needed to create articles. Set by
   * name (the field exists only with Knowledge). Null if the org has no Knowledge licence left.
   * @param language LanguageLocaleKey for the user
   * @return the inserted user, or null
   */
  private static User knowledgeUser(String language) {
    User user = new User(
      ProfileId = [
        SELECT Id
        FROM Profile
        WHERE PermissionsModifyAllData = TRUE AND UserType = 'Standard'
        ORDER BY CreatedDate
        LIMIT 1
      ]
      .Id,
      LastName = 'Knowledge Test',
      Alias = 'kbtest',
      Email = 'knowledge.test@example.com',
      Username = 'knowledge.test.' +
        String.valueOf(Crypto.getRandomInteger()).replace('-', '') +
        '@example.com',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = language,
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'America/Los_Angeles'
    );
    user.put('UserPermissionsKnowledgeUser', true);
    try {
      System.runAs(new User(Id = UserInfo.getUserId())) {
        insert user;
      }
    } catch (DmlException e) {
      return null;
    }
    return user;
  }

  // ---- validator ----

  @IsTest
  static void validatorMarksArticleTargets() {
    if (!knowledgeAvailable()) {
      return;
    }
    SearchTarget target = new SchemaValidator().validate(articleConfig());
    Assert.isTrue(target.isKnowledge);
    Assert.areEqual('PublishStatus', target.publishStatusField.getName());
    Assert.areEqual('Language', target.languageField.getName());
    Assert.isNull(target.dataCategory, 'No category configured');
    Assert.isFalse(accountTarget().isKnowledge);
  }

  @IsTest
  static void visibleCategoryIsKept() {
    if (!knowledgeAvailable()) {
      return;
    }
    SearchTarget target = articleTargetWithCategory();
    Assert.areEqual('Products', target.dataCategory.groupName);
    Assert.areEqual('Nimbus_Cloud', target.dataCategory.categoryName);
    Assert.areEqual('BELOW', target.dataCategory.operator);
  }

  @IsTest
  static void invisibleOrHalfConfiguredCategorySkipsTheObject() {
    if (!knowledgeAvailable()) {
      return;
    }
    KnowledgeSupport.visibleCategoriesOverride = new Map<String, Set<String>>{
      'Products' => new Set<String>{ 'Nimbus_Cloud' }
    };
    SearchConfig.ObjectConfig notVisible = articleConfig();
    notVisible.dataCategoryGroup = 'Products';
    notVisible.dataCategory = 'All';
    Assert.isNull(
      new SchemaValidator().validate(notVisible),
      'Fail closed: no results rather than more'
    );

    SearchConfig.ObjectConfig groupOnly = articleConfig();
    groupOnly.dataCategoryGroup = 'Products';
    Assert.isNull(
      new SchemaValidator().validate(groupOnly),
      'A group without a category is a broken restriction'
    );
  }

  @IsTest
  static void categoryFieldsAreIgnoredOnOtherObjects() {
    SearchConfig.ObjectConfig objectConfig = new SearchConfig.ObjectConfig();
    objectConfig.developerName = 'Accounts';
    objectConfig.objectApiName = 'Account';
    objectConfig.titleField = 'Name';
    objectConfig.dataCategoryGroup = 'Products';
    objectConfig.dataCategory = 'Nimbus_Cloud';
    SearchTarget target = new SchemaValidator().validate(objectConfig);
    Assert.isNotNull(target);
    Assert.isNull(target.dataCategory);
  }

  // ---- query builder ----

  @IsTest
  static void soslAlwaysFiltersPublishedAndLanguage() {
    if (!knowledgeAvailable()) {
      return;
    }
    SearchTarget target = new SchemaValidator().validate(articleConfig());
    target.knowledgeLanguage = 'en_US';
    String sosl = SearchQueryBuilder.buildSosl(
      'reset',
      new List<SearchTarget>{ target, accountTarget() },
      null,
      11
    );
    Assert.isTrue(
      sosl.contains(
        'Knowledge__kav(Id, Title WHERE PublishStatus = \'Online\' AND Language = \'en_US\' LIMIT 11)'
      ),
      sosl
    );
    Assert.isFalse(sosl.contains('WITH DATA CATEGORY'), sosl);

    target.knowledgeLanguage = null;
    sosl = SearchQueryBuilder.buildSosl(
      'reset',
      new List<SearchTarget>{ target },
      null,
      11
    );
    Assert.isTrue(
      sosl.contains('WHERE PublishStatus = \'Online\' LIMIT 11'),
      'No valid language: SOSL uses the platform default. ' + sosl
    );
  }

  @IsTest
  static void dataCategoryClauseInSoslAndSoql() {
    if (!knowledgeAvailable()) {
      return;
    }
    SearchTarget target = articleTargetWithCategory();
    target.knowledgeLanguage = 'en_US';
    String sosl = SearchQueryBuilder.buildSosl(
      'reset',
      new List<SearchTarget>{ target },
      null,
      11
    );
    Assert.isTrue(
      sosl.endsWith(
        'LIMIT 11) WITH DATA CATEGORY Products__c BELOW Nimbus_Cloud__c'
      ),
      sosl
    );

    SearchQueryBuilder.QuerySpec spec = SearchQueryBuilder.buildSoql(
      target,
      null,
      11
    );
    Assert.isTrue(
      spec.query.contains(
        'WHERE PublishStatus = :p0 AND Language = :p1 WITH DATA CATEGORY Products__c BELOW Nimbus_Cloud__c ORDER BY'
      ),
      spec.query
    );
    Assert.areEqual('Online', spec.binds.get('p0'));
    Assert.areEqual('en_US', spec.binds.get('p1'));
  }

  @IsTest
  static void categoryTargetCanNotShareASoslQuery() {
    if (!knowledgeAvailable()) {
      return;
    }
    try {
      SearchQueryBuilder.buildSosl(
        'reset',
        new List<SearchTarget>{ articleTargetWithCategory(), accountTarget() },
        null,
        11
      );
      Assert.fail('Expected IllegalArgumentException');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('on its own'));
    }
  }

  // ---- service ----

  @IsTest
  static void draftsNeverComeBack() {
    if (!knowledgeAvailable()) {
      return;
    }
    User author = knowledgeUser('en_US');
    if (author == null) {
      return;
    }
    System.runAs(author) {
      registerConfig();
      SObject draft = Schema.getGlobalDescribe()
        .get(ARTICLE_OBJECT)
        .newSObject();
      draft.put('Title', 'Gadget draft article');
      draft.put('UrlName', 'gadget-draft-' + Crypto.getRandomInteger());
      draft.put('Language', 'en_US');
      insert draft;
      Account account = new Account(Name = 'Gadget account');
      insert account;
      Test.setFixedSearchResults(new List<Id>{ draft.Id, account.Id });

      SearchRequestDto request = SearchTestFactory.request('gadget');
      request.language = 'en_US';
      SearchResponseDto response = new SearchService().search(request);

      Assert.areEqual(1, response.groups.size(), 'Only accounts');
      Assert.areEqual('Account', response.groups[0].objectApiName);
    }
  }

  @IsTest
  static void categoryObjectGetsItsOwnSoslQuery() {
    if (!knowledgeAvailable()) {
      return;
    }
    // A real query needs a real category (an override would make SOSL reject the group), so
    // this uses one of the org's own; data category groups are metadata tests can't create.
    Map<String, Set<String>> real = KnowledgeSupport.describeVisibleCategories();
    String groupName;
    for (String candidate : real.keySet()) {
      if (!real.get(candidate).isEmpty()) {
        groupName = candidate;
      }
    }
    if (groupName == null) {
      return;
    }
    Search_Object__mdt articles = registerConfig();
    articles.Data_Category_Group__c = groupName;
    articles.Data_Category__c = new List<String>(real.get(groupName))[0];
    Test.startTest();
    new SearchService().search(SearchTestFactory.request('gadget'));
    Integer soslQueries = Limits.getSoslQueries();
    Test.stopTest();
    Assert.areEqual(2, soslQueries, 'Accounts, then articles on their own');
  }

  @IsTest
  static void browseLeavesKnowledgeOutWithoutAValidLanguage() {
    if (!knowledgeAvailable()) {
      return;
    }
    // A language that's not a Knowledge language here. If the org has made it one, the case
    // can't be tested.
    User frenchUser = knowledgeUser('fr');
    if (frenchUser == null) {
      return;
    }
    System.runAs(frenchUser) {
      SearchTarget probe = new SchemaValidator().validate(articleConfig());
      if (KnowledgeSupport.resolveLanguage(probe.languageField, null) != null) {
        return;
      }
      registerConfig();
      SearchRequestDto request = SearchTestFactory.request('');
      request.selectedFacets.add(
        SearchTestFactory.selection(
          ARTICLE_OBJECT,
          'Language',
          new List<String>{
            probe.languageField.getPicklistValues()[0].getValue()
          }
        )
      );
      Integer before = Limits.getQueries();
      SearchResponseDto response = new SearchService().search(request);
      Assert.areEqual(
        before,
        Limits.getQueries(),
        'No SOQL for Knowledge: it would return every language'
      );
      Assert.isTrue(response.groups.isEmpty());

      // Same request with a valid language from the component runs the query.
      request.language = probe.languageField.getPicklistValues()[0].getValue();
      new SearchService().search(request);
      Assert.areEqual(before + 1, Limits.getQueries());
    }
  }
}
