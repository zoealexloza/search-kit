/**
 * Knowledge article support: recognises Knowledge article objects, resolves the language to
 * search in, and validates a configured data category for the running user.
 *
 * Knowledge isn't enabled in every org, so nothing here refers to Knowledge__kav or the
 * KbManagement namespace at compile time (that would make Knowledge a package dependency, and
 * even a describe throws NoAccessException for users without Knowledge access). Everything goes
 * through names and dynamic describe calls.
 *
 * Why the service adds these filters itself (not as admin config): SOQL on an article object has
 * no implicit filter, so an internal user would get drafts, archived versions and every
 * language; and a Language value that isn't an active Knowledge language makes the query throw.
 * Guests and customers already get only published articles in their channel and visible
 * categories from the platform; the filters are a second layer and cover internal users.
 *
 * inherited sharing: describe calls only, no queries or DML.
 */
public inherited sharing class KnowledgeSupport {
  /** Data_Category_Operator__c values. */
  public static final String OP_AT = 'at';
  public static final String OP_AT_OR_BELOW = 'at_or_below';

  public static final String PUBLISH_STATUS_FIELD = 'PublishStatus';
  public static final String LANGUAGE_FIELD = 'Language';
  public static final String PUBLISHED = 'Online';

  /** Lightning Knowledge lets admins name the article object, but it always ends in __kav. */
  private static final String ARTICLE_SUFFIX = '__kav';
  /** Data category describes take the abstract type, not the article object's name. */
  private static final String CATEGORY_SOBJECT = 'KnowledgeArticleVersion';

  private static final Pattern API_NAME = Pattern.compile(
    '^[A-Za-z][A-Za-z0-9_]{0,79}$'
  );

  /**
   * Tests set this instead of relying on the org's data categories (metadata that tests can't
   * create): canonical group name to the canonical category names visible to the running user.
   */
  @TestVisible
  private static Map<String, Set<String>> visibleCategoriesOverride;

  /**
   * Whether the object is a Knowledge article version object.
   * @param objectApiName object API name (canonical, from describe)
   * @return true for article objects such as Knowledge__kav
   */
  public static Boolean isKnowledgeObject(String objectApiName) {
    return objectApiName != null &&
      objectApiName.toLowerCase().endsWith(ARTICLE_SUFFIX);
  }

  /**
   * Picks the language to search in. The visitor's site language comes from the component
   * (Apex sees a guest user's own language, not the one picked on the site), so it is untrusted:
   * it is used only if it is an active Knowledge language, or if its base language is (es_MX
   * becomes es). Otherwise the running user's language is tried the same way.
   * @param languageField the article object's Language field describe
   * @param requested language sent by the component (may be null)
   * @return an active Knowledge language in its canonical spelling, or null if neither is one
   */
  public static String resolveLanguage(
    Schema.DescribeFieldResult languageField,
    String requested
  ) {
    List<String> activeLanguages = new List<String>();
    for (Schema.PicklistEntry entry : languageField.getPicklistValues()) {
      if (entry.isActive()) {
        activeLanguages.add(entry.getValue());
      }
    }
    return resolveLanguage(activeLanguages, requested);
  }

  /**
   * Matching logic of resolveLanguage, separate so it can be tested without Knowledge.
   * @param activeLanguages active Knowledge languages, canonical spelling
   * @param requested language sent by the component (may be null)
   * @return the first of requested and the user's language that is active, or null
   */
  @TestVisible
  private static String resolveLanguage(
    List<String> activeLanguages,
    String requested
  ) {
    Map<String, String> active = new Map<String, String>();
    for (String language : activeLanguages) {
      active.put(language.toLowerCase(), language);
    }
    for (
      String candidate : new List<String>{ requested, UserInfo.getLanguage() }
    ) {
      if (candidate == null) {
        continue;
      }
      // LWC's @salesforce/i18n/lang is BCP 47 (en-US); Salesforce language codes use en_US.
      String key = candidate.replace('-', '_').toLowerCase();
      if (active.containsKey(key)) {
        return active.get(key);
      }
      // A regional variant falls back to its base language (es_MX to es) before the next
      // candidate, so a Mexican Spanish site still gets Spanish articles.
      String base = key.substringBefore('_');
      if (active.containsKey(base)) {
        return active.get(base);
      }
    }
    return null;
  }

  /**
   * Validates a configured data category for the running user. Group and category must be
   * visible to that user: a category the user can't see (including the parent of one they can)
   * makes the query throw, and dropping the restriction would show more than the admin chose.
   * @param groupName Data_Category_Group__c
   * @param categoryName Data_Category__c
   * @param operator Data_Category_Operator__c; blank means at_or_below
   * @return the filter with canonical names, or null if anything is invalid or not visible
   */
  public static SearchTarget.DataCategoryFilter validateCategory(
    String groupName,
    String categoryName,
    String operator
  ) {
    String soslOperator = toQueryOperator(operator);
    if (
      soslOperator == null ||
      !isApiName(groupName) ||
      !isApiName(categoryName)
    ) {
      return null;
    }
    Map<String, Set<String>> visible = visibleCategoriesOverride != null
      ? visibleCategoriesOverride
      : describeVisibleCategories();
    String visibleGroup = findIgnoringCase(visible.keySet(), groupName);
    String visibleCategory = visibleGroup == null
      ? null
      : findIgnoringCase(visible.get(visibleGroup), categoryName);
    if (visibleCategory == null) {
      return null;
    }
    SearchTarget.DataCategoryFilter filter = new SearchTarget.DataCategoryFilter();
    filter.groupName = visibleGroup;
    filter.categoryName = visibleCategory;
    filter.operator = soslOperator;
    return filter;
  }

  /**
   * Finds a name in a set of describe names, ignoring case.
   * @param names canonical names
   * @param wanted configured name
   * @return the canonical spelling, or null if it isn't in the set
   */
  private static String findIgnoringCase(Set<String> names, String wanted) {
    for (String name : names) {
      if (name.equalsIgnoreCase(wanted)) {
        return name;
      }
    }
    return null;
  }

  private static String toQueryOperator(String operator) {
    if (String.isBlank(operator) || operator == OP_AT_OR_BELOW) {
      // SOSL and SOQL BELOW include the category itself.
      return 'BELOW';
    }
    return operator == OP_AT ? 'AT' : null;
  }

  private static Boolean isApiName(String value) {
    return value != null && API_NAME.matcher(value).matches();
  }

  /**
   * Every data category group for articles, with the categories in it that the running user can
   * see. The describe calls already return only what the running user can see.
   * @return canonical group name to canonical category names; empty if there are none, or if
   *         the user can't describe them (no Knowledge access)
   */
  @TestVisible
  private static Map<String, Set<String>> describeVisibleCategories() {
    Map<String, Set<String>> visible = new Map<String, Set<String>>();
    try {
      List<DataCategoryGroupSobjectTypePair> pairs = new List<DataCategoryGroupSobjectTypePair>();
      for (
        DescribeDataCategoryGroupResult groupResult : Schema.describeDataCategoryGroups(
          new List<String>{ CATEGORY_SOBJECT }
        )
      ) {
        DataCategoryGroupSobjectTypePair pair = new DataCategoryGroupSobjectTypePair();
        pair.setSobject(CATEGORY_SOBJECT);
        pair.setDataCategoryGroupName(groupResult.getName());
        pairs.add(pair);
      }
      if (pairs.isEmpty()) {
        return visible;
      }
      for (
        DescribeDataCategoryGroupStructureResult structure : Schema.describeDataCategoryGroupStructures(
          pairs,
          false
        )
      ) {
        Set<String> names = new Set<String>();
        List<DataCategory> pending = new List<DataCategory>(
          structure.getTopCategories()
        );
        while (!pending.isEmpty()) {
          DataCategory category = pending.remove(pending.size() - 1);
          names.add(category.getName());
          pending.addAll(category.getChildCategories());
        }
        visible.put(structure.getName(), names);
      }
    } catch (Exception e) {
      // NoAccessException without Knowledge access; any other describe failure means the
      // category can't be validated, so the caller fails closed.
      System.debug(
        LoggingLevel.FINE,
        'SiteSearch: data categories not available: ' + e.getTypeName()
      );
    }
    return visible;
  }
}
