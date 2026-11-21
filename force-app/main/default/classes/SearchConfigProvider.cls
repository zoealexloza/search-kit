/**
 * Loads a search configuration from Custom Metadata and returns it as a typed SearchConfig.
 *
 * Uses getAll() only: it is served from the platform's metadata cache and consumes no SOQL
 * limits, so no extra caching layer is needed here. getAll() returns metadata relationship
 * fields (e.g. Search_Object__mdt.Search_Config__c) as the parent record's Id, so children are
 * joined on Id. (In Apex these fields are Id-typed, so a 15-character Id compares equal to
 * its 18-character form.)
 *
 * inherited sharing: reads Custom Metadata only, which sharing does not apply to.
 */
public inherited sharing class SearchConfigProvider {
  // Test seams. getAll() cannot be stubbed and CMDT records cannot be inserted in tests,
  // so tests set these lists instead. Null means "use getAll()".
  @TestVisible
  private static List<Search_Config__mdt> configRecords;
  @TestVisible
  private static List<Search_Object__mdt> objectRecords;
  @TestVisible
  private static List<Search_Filter_Rule__mdt> filterRuleRecords;
  @TestVisible
  private static List<Search_Boost_Rule__mdt> boostRuleRecords;
  @TestVisible
  private static List<Search_Facet__mdt> facetRecords;

  @TestVisible
  private static final Integer DEFAULT_RESULTS_PER_OBJECT = 10;
  @TestVisible
  private static final Integer MAX_RESULTS_PER_OBJECT = 50;

  /**
   * Returns the active configuration with the given DeveloperName (case-insensitive),
   * including its active objects and their filter rules, boost rules and facets.
   * @param configName DeveloperName of a Search_Config__mdt record
   * @return the typed configuration
   * @throws SiteSearchException if the name is blank, unknown, or the config is inactive
   */
  public SearchConfig getActiveConfig(String configName) {
    Search_Config__mdt record = String.isBlank(configName)
      ? null
      : findConfig(configName.trim());
    if (record == null || !record.Is_Active__c) {
      throw new SiteSearchException(System.Label.Search_Error_Config_Not_Found);
    }
    return buildConfig(record);
  }

  /**
   * Returns every active configuration, sorted by label (then DeveloperName), for the
   * Experience Builder property panel. Child records are not loaded.
   * @return active Search_Config__mdt records; empty if there are none
   */
  public List<Search_Config__mdt> getActiveConfigs() {
    List<ConfigByLabel> sortable = new List<ConfigByLabel>();
    for (
      Search_Config__mdt record : configRecords != null
        ? configRecords
        : Search_Config__mdt.getAll().values()
    ) {
      if (record.Is_Active__c) {
        sortable.add(new ConfigByLabel(record));
      }
    }
    sortable.sort();
    List<Search_Config__mdt> active = new List<Search_Config__mdt>();
    for (ConfigByLabel entry : sortable) {
      active.add(entry.record);
    }
    return active;
  }

  /** Sorts configs by label, then DeveloperName, so the picklist order is predictable. */
  private class ConfigByLabel implements Comparable {
    private final Search_Config__mdt record;

    private ConfigByLabel(Search_Config__mdt record) {
      this.record = record;
    }

    /**
     * Orders by label, then DeveloperName (which is unique, so the order is total).
     * @param other another ConfigByLabel
     * @return negative, zero or positive, as Comparable requires
     */
    public Integer compareTo(Object other) {
      Search_Config__mdt that = ((ConfigByLabel) other).record;
      Integer byLabel = (record.Label == null ? '' : record.Label)
        .compareTo(that.Label == null ? '' : that.Label);
      return byLabel != 0
        ? byLabel
        : record.DeveloperName.compareTo(that.DeveloperName);
    }
  }

  private static Search_Config__mdt findConfig(String configName) {
    for (
      Search_Config__mdt record : configRecords != null
        ? configRecords
        : Search_Config__mdt.getAll().values()
    ) {
      if (configName.equalsIgnoreCase(record.DeveloperName)) {
        return record;
      }
    }
    return null;
  }

  private static SearchConfig buildConfig(Search_Config__mdt record) {
    SearchConfig config = new SearchConfig();
    config.developerName = record.DeveloperName;
    config.label = record.Label;
    config.resultsPerObject = clampResultsPerObject(
      record.Results_Per_Object__c
    );
    config.allowAgentAccess = record.Allow_Agent_Access__c == true;

    Map<Id, SearchConfig.ObjectConfig> objectsById = new Map<Id, SearchConfig.ObjectConfig>();
    for (Search_Object__mdt objectRecord : getObjectRecords()) {
      if (
        objectRecord.Is_Active__c && objectRecord.Search_Config__c == record.Id
      ) {
        objectsById.put(objectRecord.Id, toObjectConfig(objectRecord));
      }
    }
    if (!objectsById.isEmpty()) {
      attachRules(objectsById);
      attachFacets(objectsById);
    }

    config.objects.addAll(objectsById.values());
    config.objects.sort();
    for (SearchConfig.ObjectConfig objectConfig : config.objects) {
      objectConfig.facets.sort();
    }
    return config;
  }

  private static void attachRules(
    Map<Id, SearchConfig.ObjectConfig> objectsById
  ) {
    for (Search_Filter_Rule__mdt rule : getFilterRuleRecords()) {
      SearchConfig.ObjectConfig parent = objectsById.get(rule.Search_Object__c);
      if (parent != null) {
        parent.filterRules.add(
          toRule(
            rule.DeveloperName,
            rule.Field__c,
            rule.Operator__c,
            rule.Value__c
          )
        );
      }
    }
    for (Search_Boost_Rule__mdt rule : getBoostRuleRecords()) {
      SearchConfig.ObjectConfig parent = objectsById.get(rule.Search_Object__c);
      if (parent != null) {
        SearchConfig.RuleConfig boost = toRule(
          rule.DeveloperName,
          rule.Field__c,
          rule.Operator__c,
          rule.Value__c
        );
        boost.points = rule.Points__c == null ? 0 : rule.Points__c.intValue();
        parent.boostRules.add(boost);
      }
    }
  }

  private static void attachFacets(
    Map<Id, SearchConfig.ObjectConfig> objectsById
  ) {
    for (Search_Facet__mdt facet : getFacetRecords()) {
      SearchConfig.ObjectConfig parent = objectsById.get(
        facet.Search_Object__c
      );
      if (parent != null) {
        SearchConfig.FacetConfig facetConfig = new SearchConfig.FacetConfig();
        facetConfig.developerName = facet.DeveloperName;
        facetConfig.fieldApiName = facet.Field__c;
        facetConfig.label = facet.Label__c;
        facetConfig.sortOrder = facet.Sort_Order__c;
        parent.facets.add(facetConfig);
      }
    }
  }

  private static SearchConfig.ObjectConfig toObjectConfig(
    Search_Object__mdt record
  ) {
    SearchConfig.ObjectConfig objectConfig = new SearchConfig.ObjectConfig();
    objectConfig.developerName = record.DeveloperName;
    objectConfig.objectApiName = record.Object__c;
    objectConfig.titleField = record.Title_Field__c;
    for (
      String detailField : new List<String>{
        record.Detail_Field_1__c,
        record.Detail_Field_2__c,
        record.Detail_Field_3__c
      }
    ) {
      if (String.isNotBlank(detailField)) {
        objectConfig.detailFields.add(detailField);
      }
    }
    objectConfig.iconName = record.Icon_Name__c;
    objectConfig.sectionLabel = String.isNotBlank(record.Section_Label__c)
      ? record.Section_Label__c
      : record.Label;
    objectConfig.sortOrder = record.Sort_Order__c;
    objectConfig.dataCategoryGroup = record.Data_Category_Group__c;
    objectConfig.dataCategory = record.Data_Category__c;
    objectConfig.dataCategoryOperator = record.Data_Category_Operator__c;
    return objectConfig;
  }

  private static SearchConfig.RuleConfig toRule(
    String developerName,
    String field,
    String operator,
    String value
  ) {
    SearchConfig.RuleConfig rule = new SearchConfig.RuleConfig();
    rule.developerName = developerName;
    rule.fieldApiName = field;
    rule.operator = operator;
    rule.value = value;
    return rule;
  }

  @TestVisible
  private static Integer clampResultsPerObject(Decimal value) {
    if (value == null) {
      return DEFAULT_RESULTS_PER_OBJECT;
    }
    return Math.max(1, Math.min(MAX_RESULTS_PER_OBJECT, value.intValue()));
  }

  private static List<Search_Object__mdt> getObjectRecords() {
    return objectRecords != null
      ? objectRecords
      : Search_Object__mdt.getAll().values();
  }

  private static List<Search_Filter_Rule__mdt> getFilterRuleRecords() {
    return filterRuleRecords != null
      ? filterRuleRecords
      : Search_Filter_Rule__mdt.getAll().values();
  }

  private static List<Search_Boost_Rule__mdt> getBoostRuleRecords() {
    return boostRuleRecords != null
      ? boostRuleRecords
      : Search_Boost_Rule__mdt.getAll().values();
  }

  private static List<Search_Facet__mdt> getFacetRecords() {
    return facetRecords != null
      ? facetRecords
      : Search_Facet__mdt.getAll().values();
  }
}
