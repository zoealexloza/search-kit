/**
 * Plain, typed copy of one search configuration as stored in Custom Metadata.
 * Built by SearchConfigProvider. Object and field names here are exactly what the admin typed
 * and are NOT validated; SchemaValidator turns each ObjectConfig into a SearchTarget.
 *
 * inherited sharing: data holder only, no queries or DML.
 */
public inherited sharing class SearchConfig {
  public String developerName;
  public String label;
  public Integer resultsPerObject;
  /** Allow_Agent_Access__c: Agentforce agents may search with this config (SiteSearchAction). */
  public Boolean allowAgentAccess = false;
  /** Active objects, sorted by sort order then developer name. */
  public List<ObjectConfig> objects = new List<ObjectConfig>();

  /** One Search_Object__mdt record with its rules and facets. */
  public class ObjectConfig implements Comparable {
    public String developerName;
    public String objectApiName;
    public String titleField;
    /** Non-blank detail fields in slot order (Detail_Field_1__c first). */
    public List<String> detailFields = new List<String>();
    public String iconName;
    public String sectionLabel;
    public Decimal sortOrder;
    /** Knowledge only: data category restriction, as configured (not yet validated). */
    public String dataCategoryGroup;
    public String dataCategory;
    /** at or at_or_below; blank means at_or_below. */
    public String dataCategoryOperator;
    public List<RuleConfig> filterRules = new List<RuleConfig>();
    public List<RuleConfig> boostRules = new List<RuleConfig>();
    /** Sorted by sort order then developer name. */
    public List<FacetConfig> facets = new List<FacetConfig>();

    /**
     * Orders objects by sort order, then developer name.
     * @param other another ObjectConfig
     * @return negative, zero or positive
     */
    public Integer compareTo(Object other) {
      ObjectConfig that = (ObjectConfig) other;
      return compareSortKeys(
        sortOrder,
        developerName,
        that.sortOrder,
        that.developerName
      );
    }
  }

  /** A filter rule or a boost rule. Points is only used by boost rules. */
  public class RuleConfig {
    public String developerName;
    public String fieldApiName;
    public String operator;
    public String value;
    public Integer points;
  }

  /** One Search_Facet__mdt record. */
  public class FacetConfig implements Comparable {
    public String developerName;
    public String fieldApiName;
    public String label;
    public Decimal sortOrder;
    /** Values to offer, separated by semicolons, as configured; blank offers all values. */
    public String values;

    /**
     * Orders facets by sort order, then developer name.
     * @param other another FacetConfig
     * @return negative, zero or positive
     */
    public Integer compareTo(Object other) {
      FacetConfig that = (FacetConfig) other;
      return compareSortKeys(
        sortOrder,
        developerName,
        that.sortOrder,
        that.developerName
      );
    }
  }

  /**
   * Orders by sort order ascending (blank sort orders last), then developer name.
   * @param orderA sort order of the first item
   * @param nameA developer name of the first item
   * @param orderB sort order of the second item
   * @param nameB developer name of the second item
   * @return negative, zero or positive, as Comparable expects
   */
  @TestVisible
  private static Integer compareSortKeys(
    Decimal orderA,
    String nameA,
    Decimal orderB,
    String nameB
  ) {
    if (orderA != orderB) {
      if (orderA == null) {
        return 1;
      }
      if (orderB == null) {
        return -1;
      }
      return orderA < orderB ? -1 : 1;
    }
    String a = nameA == null ? '' : nameA;
    String b = nameB == null ? '' : nameB;
    return a.compareTo(b);
  }
}
