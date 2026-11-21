/**
 * A configured object that passed SchemaValidator for the running user: the object exists and
 * is accessible and searchable, and every field below exists, is readable, and has a type that
 * suits its use. Field names come from describe results (canonical spelling), never from config
 * text, so the query builder only ever concatenates names the schema has confirmed.
 *
 * inherited sharing: data holder only, no queries or DML.
 */
public inherited sharing class SearchTarget {
  public String objectApiName;
  public String sectionLabel;
  public String iconName;
  public Schema.DescribeSObjectResult objectDescribe;
  public Schema.DescribeFieldResult titleField;
  public List<Schema.DescribeFieldResult> detailFields = new List<Schema.DescribeFieldResult>();
  /** Always applied, combined with AND. */
  public List<FieldRule> filterRules = new List<FieldRule>();
  public List<FieldRule> boostRules = new List<FieldRule>();
  public List<Facet> facets = new List<Facet>();

  /**
   * Knowledge article object (see KnowledgeSupport). The query builder then always adds
   * PublishStatus = 'Online' and, if knowledgeLanguage is set, the language.
   */
  public Boolean isKnowledge = false;
  public Schema.DescribeFieldResult publishStatusField;
  public Schema.DescribeFieldResult languageField;
  /** Knowledge only, optional: validated data category restriction. */
  public DataCategoryFilter dataCategory;
  /**
   * Knowledge only, set per request by SearchService: an active Knowledge language, or null if
   * neither the visitor's nor the user's language is one (SOSL then uses the platform default).
   */
  public String knowledgeLanguage;

  /**
   * Fields to select: Id, title, details, then any field a boost rule or facet needs.
   * Duplicates removed (case-insensitive), first occurrence wins.
   * @return canonical field API names
   */
  public List<String> getQueryFields() {
    List<String> fields = new List<String>();
    Set<String> seen = new Set<String>();
    addField(fields, seen, 'Id');
    addField(fields, seen, titleField.getName());
    for (Schema.DescribeFieldResult field : detailFields) {
      addField(fields, seen, field.getName());
    }
    for (FieldRule rule : boostRules) {
      addField(fields, seen, rule.field.getName());
    }
    for (Facet facet : facets) {
      addField(fields, seen, facet.field.getName());
    }
    return fields;
  }

  /**
   * Returns the facet configured on the given field, or null.
   * @param fieldApiName field API name, any case
   * @return the facet, or null if no facet uses that field
   */
  public Facet findFacet(String fieldApiName) {
    for (Facet facet : facets) {
      if (facet.field.getName().equalsIgnoreCase(fieldApiName)) {
        return facet;
      }
    }
    return null;
  }

  private static void addField(
    List<String> fields,
    Set<String> seen,
    String fieldName
  ) {
    if (seen.add(fieldName.toLowerCase())) {
      fields.add(fieldName);
    }
  }

  /**
   * A validated filter or boost rule. value is already converted to the field's type:
   * String (text and picklist values, picklists in their canonical spelling), Boolean,
   * Integer or Long (whole-number fields), Decimal (other numbers), Date or Datetime.
   * For is_true / is_false it is the Boolean being tested; for in, a non-empty List<Object> of
   * such values; for is_blank / is_not_blank, null. Relative dates are already resolved: a Date,
   * or for Datetime fields the start of a day (operator less_than or the internal at_or_after).
   */
  public class FieldRule {
    public String developerName;
    public Schema.DescribeFieldResult field;
    public String operator;
    public Object value;
    public Integer points;
  }

  /**
   * A data category visible to the running user. Names are canonical, from the data category
   * describe; operator is AT or BELOW (BELOW includes the category itself).
   */
  public class DataCategoryFilter {
    public String groupName;
    public String categoryName;
    public String operator;
  }

  /** A validated facet on a picklist, multi-select picklist or checkbox field. */
  public class Facet {
    public Schema.DescribeFieldResult field;
    public String label;
  }
}
