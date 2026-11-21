/**
 * Re-ranks the results for one object using admin-defined boost rules.
 *
 * SOSL returns results in its own relevance order and offers no way to influence ranking.
 * This class keeps that order as the baseline and adds points for rules each record matches,
 * so admins can promote (or, with negative points, demote) records by field value.
 *
 * inherited sharing: works on records already queried, no queries or DML.
 */
public inherited sharing class BoostRuleEngine {
  /**
   * Scores and sorts records. Highest score first; ties keep their original order.
   * @param records results in source order (SOSL relevance, or SOQL sort order in browse mode)
   * @param rules validated boost rules for this object
   * @return scored records, best first
   */
  public static List<ScoredRecord> rank(
    List<SObject> records,
    List<SearchTarget.FieldRule> rules
  ) {
    List<ScoredRecord> scored = new List<ScoredRecord>();
    Integer resultCount = records.size();
    for (Integer i = 0; i < resultCount; i++) {
      scored.add(
        new ScoredRecord(
          records[i],
          i,
          score(resultCount, i, records[i], rules)
        )
      );
    }
    scored.sort();
    return scored;
  }

  /**
   * The scoring formula:
   *
   *     score = baseScore + sum of points of every boost rule the record matches
   *     baseScore = resultCount - sourceIndex
   *
   * baseScore turns the source order into numbers: with 10 results the most relevant record
   * gets 10, the least relevant gets 1. Because each step is worth exactly 1 point, a boost of
   * N points lets a record overtake at most N records that rank above it on relevance alone
   * (more if those records match fewer rules). For example, with Featured +50, a featured
   * record from position 8 of 10 (base 3, score 53) moves above a plain record in position 1
   * (score 10). Ties are broken by source order in ScoredRecord.compareTo, so equal scores never
   * reshuffle.
   *
   * @param resultCount number of records returned for this object
   * @param sourceIndex zero-based position of the record in the source order
   * @param record the record, queried with every field the rules use
   * @param rules validated boost rules
   * @return the record's score
   */
  public static Integer score(
    Integer resultCount,
    Integer sourceIndex,
    SObject record,
    List<SearchTarget.FieldRule> rules
  ) {
    Integer total = resultCount - sourceIndex;
    for (SearchTarget.FieldRule rule : rules) {
      if (matches(record, rule)) {
        total += rule.points == null ? 0 : rule.points;
      }
    }
    return total;
  }

  /**
   * Whether a record matches one rule. Text comparisons ignore case, like SOQL.
   * A blank field only matches not_equals, is_false and is_blank.
   * @param record the record
   * @param rule a validated rule
   * @return true if the rule applies to the record
   */
  public static Boolean matches(SObject record, SearchTarget.FieldRule rule) {
    Object actual = record.get(rule.field.getName());
    switch on rule.operator {
      when 'is_true', 'is_false' {
        // Checkboxes are never null in Salesforce; treat null as false anyway.
        return (actual == true) == (Boolean) rule.value;
      }
      when 'is_blank' {
        return isBlank(actual);
      }
      when 'is_not_blank' {
        return !isBlank(actual);
      }
      when 'in' {
        return matchesAny(actual, (List<Object>) rule.value, rule.field);
      }
      when 'at_or_after' {
        Integer comparison = compareValues(actual, rule.value);
        return comparison != null && comparison >= 0;
      }
      when 'equals' {
        return valuesEqual(actual, rule.value);
      }
      when 'not_equals' {
        return !valuesEqual(actual, rule.value);
      }
      when 'includes' {
        return actual != null &&
          containsIgnoreCase(
            String.valueOf(actual).split(';'),
            (String) rule.value
          );
      }
      when 'contains' {
        return actual != null &&
          String.valueOf(actual).containsIgnoreCase((String) rule.value);
      }
      when 'greater_than' {
        Integer comparison = compareValues(actual, rule.value);
        return comparison != null && comparison > 0;
      }
      when 'less_than' {
        Integer comparison = compareValues(actual, rule.value);
        return comparison != null && comparison < 0;
      }
      when else {
        return false;
      }
    }
  }

  /**
   * Blank as SOQL sees it: null, or (for values set in memory) empty or whitespace-only text.
   * @param actual the record's field value
   * @return true if blank
   */
  private static Boolean isBlank(Object actual) {
    return actual == null ||
      (actual instanceof String && String.isBlank((String) actual));
  }

  /**
   * The "in" operator: the value equals any rule value. On a multi-select picklist, any selected
   * value equals any rule value (the same as SOQL INCLUDES with several values).
   * @param actual the record's field value
   * @param expected the rule's typed values
   * @param field the rule's field
   * @return true if any value matches
   */
  private static Boolean matchesAny(
    Object actual,
    List<Object> expected,
    Schema.DescribeFieldResult field
  ) {
    if (actual == null) {
      return false;
    }
    Boolean multiSelect = field.getType() == Schema.DisplayType.MULTIPICKLIST;
    List<String> selected = multiSelect
      ? String.valueOf(actual).split(';')
      : null;
    for (Object value : expected) {
      Boolean found = multiSelect
        ? containsIgnoreCase(selected, (String) value)
        : valuesEqual(actual, value);
      if (found) {
        return true;
      }
    }
    return false;
  }

  private static Boolean valuesEqual(Object actual, Object expected) {
    if (actual == null) {
      return false;
    }
    if (expected instanceof String) {
      return String.valueOf(actual).equalsIgnoreCase((String) expected);
    }
    if (expected instanceof Boolean) {
      return actual == expected;
    }
    Integer comparison = compareValues(actual, expected);
    return comparison != null && comparison == 0;
  }

  /**
   * Compares a field value with a rule value of the same kind (number, date or datetime).
   * @param actual the record's field value
   * @param expected the rule's typed value
   * @return -1, 0 or 1; null if either value is missing or the types cannot be compared
   */
  private static Integer compareValues(Object actual, Object expected) {
    if (actual == null || expected == null) {
      return null;
    }
    // Date before Datetime: in Apex a Date value is also "instanceof Datetime"
    // (verified in a scratch org, see docs/PROGRESS.md), but not the other way round.
    if (expected instanceof Date) {
      return actual instanceof Date
        ? sign(((Date) expected).daysBetween((Date) actual))
        : null;
    }
    if (expected instanceof Datetime) {
      Boolean actualIsDatetime =
        actual instanceof Datetime && !(actual instanceof Date);
      return actualIsDatetime
        ? sign(((Datetime) actual).getTime() - ((Datetime) expected).getTime())
        : null;
    }
    if (expected instanceof Decimal) {
      // Integer and Long values (field or rule) convert through their string form.
      Decimal actualNumber = Decimal.valueOf(String.valueOf(actual));
      Decimal expectedNumber = Decimal.valueOf(String.valueOf(expected));
      return actualNumber == expectedNumber
        ? 0
        : (actualNumber > expectedNumber ? 1 : -1);
    }
    return null;
  }

  /**
   * Sign of a number.
   * @param value any number
   * @return -1, 0 or 1
   */
  private static Integer sign(Long value) {
    return value == 0 ? 0 : (value > 0 ? 1 : -1);
  }

  /**
   * Whether a list contains a value, ignoring case and surrounding spaces.
   * @param values values from a multi-select picklist
   * @param expected the value to look for
   * @return true if found
   */
  private static Boolean containsIgnoreCase(
    List<String> values,
    String expected
  ) {
    for (String value : values) {
      if (value.trim().equalsIgnoreCase(expected)) {
        return true;
      }
    }
    return false;
  }

  /** A record with its score and original position. */
  public class ScoredRecord implements Comparable {
    public SObject record;
    public Integer sourceIndex;
    public Integer score;

    /**
     * Creates a scored record.
     * @param record the record
     * @param sourceIndex zero-based position in the source order
     * @param score the score from BoostRuleEngine.score
     */
    public ScoredRecord(SObject record, Integer sourceIndex, Integer score) {
      this.record = record;
      this.sourceIndex = sourceIndex;
      this.score = score;
    }

    /**
     * Higher score first; equal scores keep source order, so the sort is stable.
     * @param other another ScoredRecord
     * @return negative if this record ranks first, positive if the other does
     */
    public Integer compareTo(Object other) {
      ScoredRecord that = (ScoredRecord) other;
      if (score != that.score) {
        return score > that.score ? -1 : 1;
      }
      return sourceIndex - that.sourceIndex;
    }
  }
}
