/**
 * Search response returned to the LWC. All values are already formatted for display
 * (picklist labels, locale-formatted dates and numbers), so the component only renders text.
 *
 * inherited sharing: data holder only, no queries or DML.
 */
public inherited sharing class SearchResponseDto {
  public static final String MODE_SEARCH = 'search';
  public static final String MODE_BROWSE = 'browse';
  public static final String MODE_NONE = 'none';

  /**
   * The visitor's term after sanitizing (for messages such as "No results for ...").
   * A term search only ran if mode is search; shorter terms are returned but not searched.
   */
  @AuraEnabled
  public String searchTerm;

  /** search (SOSL on a term), browse (SOQL on facet selections only) or none. */
  @AuraEnabled
  public String mode = MODE_NONE;

  /** Groups that have at least one result, in config sort order. */
  @AuraEnabled
  public List<ObjectGroup> groups = new List<ObjectGroup>();

  /**
   * Facets for every searched object, whether or not it has results. When the request is scoped
   * to some objects, only their facets are returned.
   */
  @AuraEnabled
  public List<FacetGroup> facets = new List<FacetGroup>();

  /**
   * Every object the visitor can search with this config, in config sort order, whatever the
   * request's scope. The component builds its object tabs from this list.
   */
  @AuraEnabled
  public List<SearchableObject> objects = new List<SearchableObject>();

  /** An object the visitor can search (one tab). */
  public class SearchableObject {
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public String sectionLabel;
    @AuraEnabled
    public String iconName;
    /** Whether the object has facets, so the panel can stay in place on tabs without any. */
    @AuraEnabled
    public Boolean hasFacets;
  }

  /** Results for one object. */
  public class ObjectGroup {
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public String sectionLabel;
    @AuraEnabled
    public String iconName;
    @AuraEnabled
    public Integer totalShown;
    /** True if more results exist beyond totalShown. */
    @AuraEnabled
    public Boolean hasMore;
    @AuraEnabled
    public List<Result> results = new List<Result>();
  }

  /** One record in the results. */
  public class Result {
    @AuraEnabled
    public Id recordId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public List<Detail> details = new List<Detail>();
    /** Final score after boost rules (see BoostRuleEngine.score). */
    @AuraEnabled
    public Integer score;
  }

  /** One detail field: label plus formatted value. Empty values are left out. */
  public class Detail {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
  }

  /** A facet with the values a visitor can pick. */
  public class FacetGroup {
    @AuraEnabled
    public String objectApiName;
    /** The object's Section_Label__c, so facets with the same label can be told apart. */
    @AuraEnabled
    public String sectionLabel;
    @AuraEnabled
    public String fieldApiName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public List<FacetValue> values = new List<FacetValue>();
  }

  /** One selectable facet value. value is what the LWC sends back in a FacetSelection. */
  public class FacetValue {
    @AuraEnabled
    public String value;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean selected;
  }
}
