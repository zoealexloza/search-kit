/**
 * Facets: validates the visitor's selections, turns them into query conditions, and lists the
 * values each facet offers (from picklist describe, or Yes/No for checkboxes; only the
 * configured Values, in their order, when the facet has them).
 *
 * Selections come from the browser, so anything not configured is ignored without an error:
 * unknown objects, fields that are not configured facets, and values that are not active
 * picklist values (or true/false for checkboxes).
 *
 * inherited sharing: uses describe calls only, no queries or DML.
 */
public inherited sharing class FacetService {
  /** Upper bounds on request size, so a crafted request cannot burn CPU time. */
  @TestVisible
  private static final Integer MAX_SELECTIONS = 50;
  @TestVisible
  private static final Integer MAX_VALUES_PER_SELECTION = 100;

  /**
   * Validates facet selections against the configured facets.
   * @param targets validated targets
   * @param selections selections from the request (may be null)
   * @return lower-case object API name, then lower-case field API name, then typed values
   *         (picklist values in canonical spelling, or Booleans). Empty selections are left out.
   */
  public Map<String, Map<String, List<Object>>> resolveSelections(
    List<SearchTarget> targets,
    List<SearchRequestDto.FacetSelection> selections
  ) {
    Map<String, Map<String, List<Object>>> resolved = new Map<String, Map<String, List<Object>>>();
    if (selections == null) {
      return resolved;
    }
    Map<String, SearchTarget> targetsByName = indexTargets(targets);
    Integer selectionCount = Math.min(selections.size(), MAX_SELECTIONS);
    for (Integer i = 0; i < selectionCount; i++) {
      SearchRequestDto.FacetSelection selection = selections[i];
      if (
        selection == null ||
        selection.objectApiName == null ||
        selection.fieldApiName == null ||
        selection.values == null
      ) {
        continue;
      }
      SearchTarget target = targetsByName.get(
        selection.objectApiName.toLowerCase()
      );
      SearchTarget.Facet facet = target == null
        ? null
        : target.findFacet(selection.fieldApiName);
      if (facet == null) {
        continue;
      }
      String objectKey = target.objectApiName.toLowerCase();
      String fieldKey = facet.field.getName().toLowerCase();
      Map<String, List<Object>> byField = resolved.containsKey(objectKey)
        ? resolved.get(objectKey)
        : new Map<String, List<Object>>();
      List<Object> values = byField.containsKey(fieldKey)
        ? byField.get(fieldKey)
        : new List<Object>();
      addValidValues(facet, selection.values, values);
      retainOffered(values, offeredValues(target, facet));
      if (!values.isEmpty()) {
        byField.put(fieldKey, values);
        resolved.put(objectKey, byField);
      }
    }
    return resolved;
  }

  /**
   * Turns resolved selections into query conditions.
   * @param targets validated targets
   * @param resolved output of resolveSelections
   * @return lower-case object API name to conditions; objects with no restricting
   *         selection are left out
   */
  public Map<String, List<SearchQueryBuilder.Condition>> toConditions(
    List<SearchTarget> targets,
    Map<String, Map<String, List<Object>>> resolved
  ) {
    Map<String, List<SearchQueryBuilder.Condition>> conditionsByObject = new Map<String, List<SearchQueryBuilder.Condition>>();
    for (SearchTarget target : targets) {
      String objectKey = target.objectApiName.toLowerCase();
      Map<String, List<Object>> byField = resolved.get(objectKey);
      if (byField == null) {
        continue;
      }
      List<SearchQueryBuilder.Condition> conditions = new List<SearchQueryBuilder.Condition>();
      for (SearchTarget.Facet facet : target.facets) {
        List<Object> values = byField.get(facet.field.getName().toLowerCase());
        SearchQueryBuilder.Condition condition = values == null
          ? null
          : SearchQueryBuilder.fromFacet(facet, values);
        if (condition != null) {
          conditions.add(condition);
        }
      }
      if (!conditions.isEmpty()) {
        conditionsByObject.put(objectKey, conditions);
      }
    }
    return conditionsByObject;
  }

  /**
   * Lists every facet of every target with its selectable values.
   * @param targets validated targets
   * @param resolved output of resolveSelections, used to mark selected values
   * @return facet groups in target order, then facet sort order
   */
  public List<SearchResponseDto.FacetGroup> describeFacets(
    List<SearchTarget> targets,
    Map<String, Map<String, List<Object>>> resolved
  ) {
    List<SearchResponseDto.FacetGroup> groups = new List<SearchResponseDto.FacetGroup>();
    for (SearchTarget target : targets) {
      Map<String, List<Object>> byField = resolved.get(
        target.objectApiName.toLowerCase()
      );
      for (SearchTarget.Facet facet : target.facets) {
        List<SearchResponseDto.FacetValue> values = withoutExcludedValues(
          describeValues(facet, selectedValues(byField, facet)),
          facet.field,
          target.filterRules
        );
        if (values.isEmpty()) {
          continue; // Filter rules leave nothing to choose.
        }
        SearchResponseDto.FacetGroup facetGroup = new SearchResponseDto.FacetGroup();
        facetGroup.objectApiName = target.objectApiName;
        facetGroup.sectionLabel = target.sectionLabel;
        facetGroup.fieldApiName = facet.field.getName();
        facetGroup.label = facet.label;
        facetGroup.values = values;
        groups.add(facetGroup);
      }
    }
    return groups;
  }

  /**
   * The values selected for one facet, as strings.
   * @param byField one object's resolved selections (may be null)
   * @param facet the facet
   * @return the selected values; empty if none
   */
  private static Set<String> selectedValues(
    Map<String, List<Object>> byField,
    SearchTarget.Facet facet
  ) {
    Set<String> selected = new Set<String>();
    List<Object> values = byField == null
      ? null
      : byField.get(facet.field.getName().toLowerCase());
    for (Object value : values == null ? new List<Object>() : values) {
      selected.add(String.valueOf(value));
    }
    return selected;
  }

  /**
   * The values a facet offers before filter rules: the configured Values in their order, or
   * else every active picklist value (Yes and No for a checkbox).
   * @param facet the facet
   * @param selected values to mark as selected
   * @return value, label and selected flag per value
   */
  private static List<SearchResponseDto.FacetValue> describeValues(
    SearchTarget.Facet facet,
    Set<String> selected
  ) {
    // Picklist order kept in a list: it is the display order when no Values are configured.
    List<String> picklistOrder = new List<String>();
    Map<String, String> labels = new Map<String, String>();
    if (facet.field.getType() == Schema.DisplayType.BOOLEAN) {
      picklistOrder.addAll(new List<String>{ 'true', 'false' });
      labels.put('true', System.Label.Search_Value_Yes);
      labels.put('false', System.Label.Search_Value_No);
    } else {
      for (Schema.PicklistEntry entry : facet.field.getPicklistValues()) {
        if (entry.isActive()) {
          picklistOrder.add(entry.getValue());
          labels.put(entry.getValue(), entry.getLabel());
        }
      }
    }
    List<SearchResponseDto.FacetValue> values = new List<SearchResponseDto.FacetValue>();
    for (String value : facet.values == null ? picklistOrder : facet.values) {
      if (labels.containsKey(value)) {
        values.add(facetValue(value, labels.get(value), selected));
      }
    }
    return values;
  }

  /**
   * Removes facet values that the object's filter rules make impossible, so visitors are never
   * offered a choice that can only return nothing (e.g. Status = Closed when a filter keeps
   * open cases only). Multi-select picklists are left alone: a record that includes A may also
   * include B, so no value is ruled out.
   * @param values the facet's values
   * @param field the facet's field
   * @param filterRules the object's validated filter rules
   * @return the values a record passing every filter rule could have, in the same order
   */
  @TestVisible
  private static List<SearchResponseDto.FacetValue> withoutExcludedValues(
    List<SearchResponseDto.FacetValue> values,
    Schema.DescribeFieldResult field,
    List<SearchTarget.FieldRule> filterRules
  ) {
    if (field.getType() == Schema.DisplayType.MULTIPICKLIST) {
      return values;
    }
    List<SearchResponseDto.FacetValue> kept = values;
    for (SearchTarget.FieldRule rule : filterRules) {
      if (rule.field.getName() == field.getName()) {
        kept = applyRule(kept, rule);
      }
    }
    return kept;
  }

  /**
   * Keeps the values one filter rule allows. Operators that cannot rule out a single value
   * (greater_than, less_than, is_not_blank) keep everything; is_blank keeps nothing.
   * @param values current facet values
   * @param rule a filter rule on the facet's field
   * @return the values the rule allows
   */
  private static List<SearchResponseDto.FacetValue> applyRule(
    List<SearchResponseDto.FacetValue> values,
    SearchTarget.FieldRule rule
  ) {
    Set<String> listed = new Set<String>();
    Boolean keepListed;
    switch on rule.operator {
      when 'equals', 'is_true', 'is_false' {
        listed.add(String.valueOf(rule.value));
        keepListed = true;
      }
      when 'in' {
        for (Object value : (List<Object>) rule.value) {
          listed.add(String.valueOf(value));
        }
        keepListed = true;
      }
      when 'not_equals' {
        listed.add(String.valueOf(rule.value));
        keepListed = false;
      }
      when 'is_blank' {
        return new List<SearchResponseDto.FacetValue>();
      }
      when else {
        return values;
      }
    }
    List<SearchResponseDto.FacetValue> kept = new List<SearchResponseDto.FacetValue>();
    for (SearchResponseDto.FacetValue value : values) {
      if (listed.contains(value.value) == keepListed) {
        kept.add(value);
      }
    }
    return kept;
  }

  private static SearchResponseDto.FacetValue facetValue(
    String value,
    String label,
    Set<String> selected
  ) {
    SearchResponseDto.FacetValue facetValue = new SearchResponseDto.FacetValue();
    facetValue.value = value;
    facetValue.label = label;
    facetValue.selected = selected.contains(value);
    return facetValue;
  }

  /**
   * The values a facet offers: its picklist (or checkbox) values minus those its object's
   * filter rules rule out. Selections outside this set are ignored like any invalid value.
   * @param target the facet's target
   * @param facet the facet
   * @return the offered values, as strings
   */
  private static Set<String> offeredValues(
    SearchTarget target,
    SearchTarget.Facet facet
  ) {
    Set<String> offered = new Set<String>();
    for (
      SearchResponseDto.FacetValue value : withoutExcludedValues(
        describeValues(facet, new Set<String>()),
        facet.field,
        target.filterRules
      )
    ) {
      offered.add(value.value);
    }
    return offered;
  }

  /**
   * Removes values the facet doesn't offer, in place.
   * @param values typed selected values
   * @param offered output of offeredValues
   */
  private static void retainOffered(List<Object> values, Set<String> offered) {
    for (Integer i = values.size() - 1; i >= 0; i--) {
      if (!offered.contains(String.valueOf(values[i]))) {
        values.remove(i);
      }
    }
  }

  private static void addValidValues(
    SearchTarget.Facet facet,
    List<String> rawValues,
    List<Object> values
  ) {
    Set<String> seen = new Set<String>();
    for (Object value : values) {
      seen.add(String.valueOf(value));
    }
    Integer valueCount = Math.min(rawValues.size(), MAX_VALUES_PER_SELECTION);
    for (Integer i = 0; i < valueCount; i++) {
      Object typed = facet.field.getType() == Schema.DisplayType.BOOLEAN
        ? SchemaValidator.parseTypedValue(facet.field, rawValues[i])
        : SchemaValidator.canonicalPicklistValue(facet.field, rawValues[i]);
      if (typed != null && seen.add(String.valueOf(typed))) {
        values.add(typed);
      }
    }
  }

  private static Map<String, SearchTarget> indexTargets(
    List<SearchTarget> targets
  ) {
    Map<String, SearchTarget> targetsByName = new Map<String, SearchTarget>();
    for (SearchTarget target : targets) {
      targetsByName.put(target.objectApiName.toLowerCase(), target);
    }
    return targetsByName;
  }
}
