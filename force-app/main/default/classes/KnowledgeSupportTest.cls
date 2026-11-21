@IsTest
private class KnowledgeSupportTest {
  private static void setVisibleCategories() {
    KnowledgeSupport.visibleCategoriesOverride = new Map<String, Set<String>>{
      'Products' => new Set<String>{ 'Nimbus_Cloud', 'Nimbus_Mobile' }
    };
  }

  @IsTest
  static void recognisesArticleObjectsBySuffix() {
    Assert.isTrue(KnowledgeSupport.isKnowledgeObject('Knowledge__kav'));
    Assert.isTrue(
      KnowledgeSupport.isKnowledgeObject('Article__kav'),
      'Admins can name the Lightning Knowledge object'
    );
    Assert.isTrue(KnowledgeSupport.isKnowledgeObject('KNOWLEDGE__KAV'));
    Assert.isFalse(KnowledgeSupport.isKnowledgeObject('Account'));
    Assert.isFalse(KnowledgeSupport.isKnowledgeObject('Help_Article__c'));
    Assert.isFalse(KnowledgeSupport.isKnowledgeObject(null));
  }

  @IsTest
  static void requestedLanguageWinsWhenActive() {
    List<String> active = new List<String>{
      'en_US',
      'es',
      UserInfo.getLanguage()
    };
    Assert.areEqual('es', KnowledgeSupport.resolveLanguage(active, 'es'));
    Assert.areEqual(
      'es',
      KnowledgeSupport.resolveLanguage(active, 'ES'),
      'Matched ignoring case, canonical spelling returned'
    );
    if (UserInfo.getLanguage() != 'pt_BR') {
      Assert.areEqual(
        'pt_BR',
        KnowledgeSupport.resolveLanguage(new List<String>{ 'pt_BR' }, 'pt-BR'),
        'BCP 47 tag from @salesforce/i18n/lang'
      );
    }
  }

  @IsTest
  static void fallsBackToTheUsersLanguage() {
    List<String> active = new List<String>{ UserInfo.getLanguage() };
    Assert.areEqual(
      UserInfo.getLanguage(),
      KnowledgeSupport.resolveLanguage(active, 'es_MX'),
      'es_MX is not active: the user language is used'
    );
    Assert.areEqual(
      'es',
      KnowledgeSupport.resolveLanguage(
        new List<String>{ 'en_US', 'es' },
        'es-MX'
      ),
      'Regional variant falls back to its base language'
    );
    Assert.areEqual(
      UserInfo.getLanguage(),
      KnowledgeSupport.resolveLanguage(active, null)
    );
    Assert.areEqual(
      UserInfo.getLanguage(),
      KnowledgeSupport.resolveLanguage(active, '\' OR Language != \'')
    );
  }

  @IsTest
  static void noActiveLanguageGivesNull() {
    Assert.isNull(
      KnowledgeSupport.resolveLanguage(new List<String>{ 'xx' }, 'yy'),
      'Neither the requested nor the user language is active'
    );
  }

  @IsTest
  static void visibleCategoryIsAcceptedWithCanonicalNames() {
    setVisibleCategories();
    SearchTarget.DataCategoryFilter filter = KnowledgeSupport.validateCategory(
      'products',
      'NIMBUS_CLOUD',
      'at'
    );
    Assert.areEqual('Products', filter.groupName);
    Assert.areEqual('Nimbus_Cloud', filter.categoryName);
    Assert.areEqual('AT', filter.operator);

    Assert.areEqual(
      'BELOW',
      KnowledgeSupport.validateCategory(
          'Products',
          'Nimbus_Mobile',
          'at_or_below'
        )
        .operator
    );
    Assert.areEqual(
      'BELOW',
      KnowledgeSupport.validateCategory('Products', 'Nimbus_Mobile', null)
        .operator,
      'Blank operator means at or below'
    );
  }

  @IsTest
  static void invisibleOrInvalidCategoriesAreRejected() {
    setVisibleCategories();
    Assert.isNull(
      KnowledgeSupport.validateCategory('Products', 'All', 'at_or_below'),
      'Parent of a visible category is not visible'
    );
    Assert.isNull(
      KnowledgeSupport.validateCategory('Regions', 'Nimbus_Cloud', 'at'),
      'Group not visible'
    );
    Assert.isNull(
      KnowledgeSupport.validateCategory('Products', 'Nimbus_Cloud', 'above'),
      'Unknown operator'
    );
    Assert.isNull(KnowledgeSupport.validateCategory('Products', null, 'at'));
    Assert.isNull(
      KnowledgeSupport.validateCategory(null, 'Nimbus_Cloud', 'at')
    );
    Assert.isNull(
      KnowledgeSupport.validateCategory(
        'Products',
        'Nimbus_Cloud__c OR Products__c BELOW All',
        'at'
      ),
      'Injection attempt is not an API name'
    );
  }

  @IsTest
  static void realDescribeNeverThrows() {
    // No override: the org's own categories. Test orgs normally have no such group, and a user
    // without Knowledge access can't describe them; either way the result is null, not an error.
    Assert.isNull(
      KnowledgeSupport.validateCategory(
        'No_Such_Group',
        'No_Such_Category',
        'at'
      )
    );
    System.runAs(SearchTestFactory.minimumAccessUser(false)) {
      Assert.isNull(
        KnowledgeSupport.validateCategory(
          'No_Such_Group',
          'No_Such_Category',
          'at'
        )
      );
    }
  }
}
