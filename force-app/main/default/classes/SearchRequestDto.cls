/**
 * Search request sent by the LWC. Every value is untrusted input from the browser; SearchService
 * validates all of it against the configuration before use.
 *
 * inherited sharing: data holder only, no queries or DML.
 */
public inherited sharing class SearchRequestDto {
  /** DeveloperName of the Search_Config__mdt record chosen in Experience Builder. */
  @AuraEnabled
  public String configName { get; set; }

  /** Raw search text as typed by the visitor. */
  @AuraEnabled
  public String searchTerm { get; set; }

  /** Facet values the visitor selected. Values within a facet are ORed; facets are ANDed. */
  @AuraEnabled
  public List<FacetSelection> selectedFacets { get; set; }

  /** Optional results per object ("Load more" asks for more). Defaults to the config's value. */
  @AuraEnabled
  public Integer limitPerObject { get; set; }

  /**
   * Optional: search only these objects (API names, e.g. from an object tab). Empty or null
   * means every object in the config. Names that aren't searchable objects of the config are
   * ignored; if none is left, every object is searched.
   */
  @AuraEnabled
  public List<String> objectApiNames { get; set; }

  /**
   * Optional: the visitor's current site language (e.g. es), for Knowledge articles. Apex sees a
   * guest user's own language, not the one picked on the site, so the component sends it. Used
   * only if it is an active Knowledge language; otherwise the running user's language is tried.
   */
  @AuraEnabled
  public String language { get; set; }

  /**
   * Selected values for one facet. A list of these is used rather than a nested map
   * (object, then field, then values) because a flat list of typed objects deserializes
   * predictably from LWC and is simpler to validate.
   */
  public class FacetSelection {
    /** API name of the object the facet belongs to. */
    @AuraEnabled
    public String objectApiName { get; set; }

    /** API name of the facet field. */
    @AuraEnabled
    public String fieldApiName { get; set; }

    /** Selected values: picklist API values, or true / false for checkboxes. */
    @AuraEnabled
    public List<String> values { get; set; }
  }
}
