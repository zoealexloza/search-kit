/**
 * Maps ranked records to response DTOs, formatting every value server-side for the running
 * user's locale: picklist labels instead of API values, localized dates and numbers, Yes/No for
 * checkboxes, the related record's name for lookups. Rich text is reduced to plain text and
 * long values are shortened.
 *
 * inherited sharing: works on records already queried, no queries or DML.
 */
public inherited sharing class SearchResultMapper {
  /** Longest detail value shown, in characters, before it is cut and an ellipsis added. */
  @TestVisible
  private static final Integer MAX_VALUE_LENGTH = 255;

  /**
   * Builds the result group for one object.
   * @param target the validated target the records belong to
   * @param ranked records in display order
   * @param hasMore whether more records exist than are shown
   * @return the group
   */
  public static SearchResponseDto.ObjectGroup toGroup(
    SearchTarget target,
    List<BoostRuleEngine.ScoredRecord> ranked,
    Boolean hasMore
  ) {
    SearchResponseDto.ObjectGroup objectGroup = new SearchResponseDto.ObjectGroup();
    objectGroup.objectApiName = target.objectApiName;
    objectGroup.sectionLabel = target.sectionLabel;
    objectGroup.iconName = target.iconName;
    objectGroup.hasMore = hasMore;
    for (BoostRuleEngine.ScoredRecord scored : ranked) {
      objectGroup.results.add(toResult(target, scored));
    }
    objectGroup.totalShown = objectGroup.results.size();
    return objectGroup;
  }

  /**
   * Lists the objects a visitor can search, for the component's object tabs.
   * @param targets validated targets, in config sort order
   * @return one entry per target, same order
   */
  public static List<SearchResponseDto.SearchableObject> toSearchableObjects(
    List<SearchTarget> targets
  ) {
    List<SearchResponseDto.SearchableObject> objects = new List<SearchResponseDto.SearchableObject>();
    for (SearchTarget target : targets) {
      SearchResponseDto.SearchableObject searchable = new SearchResponseDto.SearchableObject();
      searchable.objectApiName = target.objectApiName;
      searchable.sectionLabel = target.sectionLabel;
      searchable.iconName = target.iconName;
      searchable.hasFacets = !target.facets.isEmpty();
      objects.add(searchable);
    }
    return objects;
  }

  private static SearchResponseDto.Result toResult(
    SearchTarget target,
    BoostRuleEngine.ScoredRecord scored
  ) {
    SearchResponseDto.Result result = new SearchResponseDto.Result();
    result.recordId = scored.record.Id;
    result.score = scored.score;
    String title = formatValue(
      scored.record.get(target.titleField.getName()),
      target.titleField
    );
    result.title = String.isBlank(title) ? System.Label.Search_Untitled : title;
    for (Schema.DescribeFieldResult field : target.detailFields) {
      SearchTarget.LookupName lookup = target.getLookupName(field);
      String value = lookup == null
        ? formatValue(scored.record.get(field.getName()), field)
        : lookupNameValue(scored.record, lookup);
      if (String.isNotBlank(value)) {
        SearchResponseDto.Detail detail = new SearchResponseDto.Detail();
        detail.label = lookup == null ? field.getLabel() : lookup.label;
        detail.value = value;
        result.details.add(detail);
      }
    }
    return result;
  }

  /**
   * The related record's name for a lookup detail. Null when the lookup is empty or the
   * visitor can't see the related record (sharing), so the detail is left out, never an ID.
   * @param record a record queried with the lookup's name path
   * @param lookup the validated lookup
   * @return display text, or null
   */
  @TestVisible
  private static String lookupNameValue(
    SObject record,
    SearchTarget.LookupName lookup
  ) {
    SObject related = record.getSObject(lookup.relationshipName);
    Object name = related == null ? null : related.get(lookup.nameField);
    return name == null
      ? null
      : String.valueOf(name).abbreviate(MAX_VALUE_LENGTH);
  }

  /**
   * Formats one field value as display text.
   * @param value the raw field value
   * @param field the field's describe result
   * @return display text; null for a null value
   */
  public static String formatValue(
    Object value,
    Schema.DescribeFieldResult field
  ) {
    if (value == null) {
      return null;
    }
    String text;
    switch on field.getType() {
      when BOOLEAN {
        text = (Boolean) value
          ? System.Label.Search_Value_Yes
          : System.Label.Search_Value_No;
      }
      when PICKLIST {
        text = picklistLabel(field, (String) value);
      }
      when MULTIPICKLIST {
        List<String> labels = new List<String>();
        for (String part : ((String) value).split(';')) {
          labels.add(picklistLabel(field, part));
        }
        text = String.join(labels, '; ');
      }
      when DATE {
        text = ((Date) value).format();
      }
      when DATETIME {
        text = ((Datetime) value).format();
      }
      when DOUBLE, CURRENCY, PERCENT {
        text = ((Decimal) value).format();
      }
      when else {
        text = String.valueOf(value);
        if (field.isHtmlFormatted()) {
          text = text.stripHtmlTags();
        }
      }
    }
    return text.abbreviate(MAX_VALUE_LENGTH);
  }

  private static String picklistLabel(
    Schema.DescribeFieldResult field,
    String value
  ) {
    for (Schema.PicklistEntry entry : field.getPicklistValues()) {
      if (entry.getValue() == value) {
        return entry.getLabel();
      }
    }
    return value;
  }
}
