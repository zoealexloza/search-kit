/**
 * Builds the SOSL query (search on a term) and SOQL queries (browse on facets only).
 * Builds strings only; SearchService runs them in user mode.
 *
 * What reaches the query text, and why each part is safe:
 * - Object and field names: only from SearchTarget, i.e. describe results (SchemaValidator).
 * - Data category names: only from the data category describe for the running user
 *   (KnowledgeSupport); the operator is the constant AT or BELOW.
 * - Knowledge filters: the constant 'Online', and a language matched against the Language
 *   picklist describe (KnowledgeSupport.resolveLanguage).
 * - Search term: reserved characters and quotes stripped (sanitizeTerm), then escaped.
 * - Filter and facet values: already converted to typed values (picklist values matched against
 *   describe, numbers, dates, booleans; relative dates such as LAST_N_DAYS:30 are already
 *   resolved to a Date or Datetime, so their text never reaches a query). SOQL binds them. SOSL cannot bind a variable number
 *   of values, so SOSL writes them as literals: typed values are formatted, strings escaped.
 *
 * inherited sharing: builds strings only, no queries or DML.
 */
public inherited sharing class SearchQueryBuilder {
  /** SOSL needs at least two characters. Shorter terms fall back to browse mode. */
  public static final Integer MIN_TERM_LENGTH = 2;
  /** Longest term searched, after sanitizing. */
  public static final Integer MAX_TERM_LENGTH = 100;
  /** Raw input is cut to this length before any regex work, to bound CPU time. */
  @TestVisible
  private static final Integer MAX_RAW_INPUT_LENGTH = 1000;

  // SOSL reserved characters: ? & | ! { } [ ] ( ) ^ ~ * : \ " ' + -
  private static final Pattern SOSL_RESERVED = Pattern.compile(
    '[?&|!{}\\[\\]()^~*:\\\\"\'+\\-]'
  );
  private static final Pattern CONTROL_CHARS = Pattern.compile('\\p{Cntrl}');

  private static final String OP_EQ = '=';
  private static final String OP_NE = '!=';
  private static final String OP_GT = '>';
  private static final String OP_GE = '>=';
  private static final String OP_LT = '<';
  private static final String OP_IN = 'IN';
  private static final String OP_INCLUDES = 'INCLUDES';

  /**
   * Turns raw visitor input into a safe SOSL search term: SOSL reserved characters, quotes and
   * control characters become spaces, whitespace is collapsed, and the result is cut to
   * MAX_TERM_LENGTH. Wildcards and boolean syntax are therefore not available to visitors.
   * @param rawTerm text as typed
   * @return sanitized term; empty string if nothing searchable is left
   */
  public static String sanitizeTerm(String rawTerm) {
    if (rawTerm == null) {
      return '';
    }
    String term = rawTerm.left(MAX_RAW_INPUT_LENGTH);
    term = SOSL_RESERVED.matcher(term).replaceAll(' ');
    term = CONTROL_CHARS.matcher(term).replaceAll(' ');
    term = term.normalizeSpace();
    if (term.length() > MAX_TERM_LENGTH) {
      term = term.left(MAX_TERM_LENGTH).trim();
    }
    return term;
  }

  /**
   * Builds one SOSL query across the given targets:
   * FIND 'term' IN ALL FIELDS RETURNING Obj1(fields WHERE ... LIMIT n), Obj2(...)
   * Results come back in SOSL relevance order, which BoostRuleEngine uses as its baseline.
   * WITH DATA CATEGORY applies to the whole query and fails if another object is in it, so a
   * target with a data category must be queried on its own.
   * @param term a term from sanitizeTerm, at least MIN_TERM_LENGTH characters
   * @param targets validated targets, at least one; a target with a data category must be alone
   * @param facetConditions extra conditions per object (key: lower-case object API name)
   * @param rowLimit LIMIT applied to each object
   * @return the SOSL query
   */
  public static String buildSosl(
    String term,
    List<SearchTarget> targets,
    Map<String, List<Condition>> facetConditions,
    Integer rowLimit
  ) {
    String categoryClause = '';
    for (SearchTarget target : targets) {
      if (target.dataCategory != null) {
        if (targets.size() > 1) {
          throw new IllegalArgumentException(
            'A target with a data category must be queried on its own'
          );
        }
        categoryClause = dataCategoryClause(target.dataCategory);
      }
    }
    List<String> returning = new List<String>();
    for (SearchTarget target : targets) {
      String whereClause = buildWhere(
        allConditions(target, facetConditions),
        null
      );
      returning.add(
        target.objectApiName +
          '(' +
          String.join(target.getQueryFields(), ', ') +
          whereClause +
          ' LIMIT ' +
          rowLimit +
          ')'
      );
    }
    return 'FIND \'' +
      String.escapeSingleQuotes(term) +
      '\' IN ALL FIELDS RETURNING ' +
      String.join(returning, ', ') +
      categoryClause;
  }

  /**
   * Renders a data category restriction. Group and category names come from the data category
   * describe (KnowledgeSupport.validateCategory), the operator is AT or BELOW.
   * @param filter the validated filter
   * @return ' WITH DATA CATEGORY Group__c BELOW Category__c'
   */
  @TestVisible
  private static String dataCategoryClause(
    SearchTarget.DataCategoryFilter filter
  ) {
    return ' WITH DATA CATEGORY ' +
      filter.groupName +
      '__c ' +
      filter.operator +
      ' ' +
      filter.categoryName +
      '__c';
  }

  /**
   * Builds a SOQL query for browse mode (facet selections, no term), with every value bound.
   * Sorted by title when the title field is sortable (long text is not), otherwise by Id.
   * @param target validated target
   * @param facetConditions extra conditions per object (key: lower-case object API name)
   * @param rowLimit LIMIT
   * @return query text plus its bind map, for Database.queryWithBinds
   */
  public static QuerySpec buildSoql(
    SearchTarget target,
    Map<String, List<Condition>> facetConditions,
    Integer rowLimit
  ) {
    QuerySpec spec = new QuerySpec();
    String orderBy = target.titleField.isSortable()
      ? target.titleField.getName() + ' ASC NULLS LAST, Id ASC'
      : 'Id ASC';
    spec.query =
      'SELECT ' +
      String.join(target.getQueryFields(), ', ') +
      ' FROM ' +
      target.objectApiName +
      buildWhere(allConditions(target, facetConditions), spec.binds) +
      (target.dataCategory == null
        ? ''
        : dataCategoryClause(target.dataCategory)) +
      ' ORDER BY ' +
      orderBy +
      ' LIMIT ' +
      rowLimit;
    return spec;
  }

  /**
   * Converts a validated filter rule to a query condition.
   * @param rule a filter rule from SearchTarget (not contains, which is boost-only)
   * @return the condition
   */
  public static Condition fromRule(SearchTarget.FieldRule rule) {
    String fieldName = rule.field.getName();
    switch on rule.operator {
      when 'not_equals' {
        return new Condition(fieldName, OP_NE, new List<Object>{ rule.value });
      }
      when 'greater_than' {
        return new Condition(fieldName, OP_GT, new List<Object>{ rule.value });
      }
      when 'at_or_after' {
        return new Condition(fieldName, OP_GE, new List<Object>{ rule.value });
      }
      when 'is_blank' {
        // Salesforce stores empty text as null, so "= null" also finds empty text fields.
        return new Condition(fieldName, OP_EQ, new List<Object>{ null });
      }
      when 'is_not_blank' {
        return new Condition(fieldName, OP_NE, new List<Object>{ null });
      }
      when 'in' {
        // On a multi-select picklist, "in" means it includes any of the values.
        return new Condition(
          fieldName,
          rule.field.getType() == Schema.DisplayType.MULTIPICKLIST
            ? OP_INCLUDES
            : OP_IN,
          (List<Object>) rule.value
        );
      }
      when 'less_than' {
        return new Condition(fieldName, OP_LT, new List<Object>{ rule.value });
      }
      when 'includes' {
        return new Condition(
          fieldName,
          OP_INCLUDES,
          new List<Object>{ rule.value }
        );
      }
      when 'equals', 'is_true', 'is_false' {
        // For is_true / is_false the validated value is the Boolean being tested.
        return new Condition(fieldName, OP_EQ, new List<Object>{ rule.value });
      }
      when else {
        throw new IllegalArgumentException(
          'Operator cannot be used in a query: ' + rule.operator
        );
      }
    }
  }

  /**
   * Converts selected facet values to a query condition: IN for picklists, INCLUDES (any of)
   * for multi-select picklists, = for checkboxes.
   * @param facet the validated facet
   * @param values typed, validated values (non-empty)
   * @return the condition, or null if the selection does not restrict anything
   *         (both true and false selected on a checkbox)
   */
  public static Condition fromFacet(
    SearchTarget.Facet facet,
    List<Object> values
  ) {
    String fieldName = facet.field.getName();
    Schema.DisplayType fieldType = facet.field.getType();
    if (fieldType == Schema.DisplayType.BOOLEAN) {
      return values.size() == 1
        ? new Condition(fieldName, OP_EQ, new List<Object>{ values[0] })
        : null;
    }
    return new Condition(
      fieldName,
      fieldType == Schema.DisplayType.MULTIPICKLIST ? OP_INCLUDES : OP_IN,
      values
    );
  }

  private static List<Condition> allConditions(
    SearchTarget target,
    Map<String, List<Condition>> facetConditions
  ) {
    List<Condition> conditions = new List<Condition>();
    if (target.isKnowledge) {
      // Always, not configurable: published versions only, in the resolved language.
      conditions.add(
        new Condition(
          target.publishStatusField.getName(),
          OP_EQ,
          new List<Object>{ KnowledgeSupport.PUBLISHED }
        )
      );
      if (target.knowledgeLanguage != null) {
        conditions.add(
          new Condition(
            target.languageField.getName(),
            OP_EQ,
            new List<Object>{ target.knowledgeLanguage }
          )
        );
      }
    }
    for (SearchTarget.FieldRule rule : target.filterRules) {
      conditions.add(fromRule(rule));
    }
    List<Condition> extra = facetConditions == null
      ? null
      : facetConditions.get(target.objectApiName.toLowerCase());
    if (extra != null) {
      conditions.addAll(extra);
    }
    return conditions;
  }

  /**
   * Renders conditions joined with AND.
   * @param conditions conditions to render
   * @param binds bind map to fill (SOQL), or null to write escaped literals (SOSL)
   * @return ' WHERE ...', or an empty string if there are no conditions
   */
  @TestVisible
  private static String buildWhere(
    List<Condition> conditions,
    Map<String, Object> binds
  ) {
    if (conditions.isEmpty()) {
      return '';
    }
    List<String> parts = new List<String>();
    for (Condition condition : conditions) {
      parts.add(render(condition, binds));
    }
    return ' WHERE ' + String.join(parts, ' AND ');
  }

  private static String render(Condition condition, Map<String, Object> binds) {
    List<String> values = new List<String>();
    for (Object value : condition.values) {
      values.add(renderValue(value, binds));
    }
    if (condition.operator == OP_IN || condition.operator == OP_INCLUDES) {
      return condition.fieldName +
        ' ' +
        condition.operator +
        ' (' +
        String.join(values, ', ') +
        ')';
    }
    return condition.fieldName + ' ' + condition.operator + ' ' + values[0];
  }

  private static String renderValue(Object value, Map<String, Object> binds) {
    if (value == null) {
      // A constant, written the same way in SOQL and SOSL.
      return 'null';
    }
    if (binds != null) {
      String name = 'p' + binds.size();
      binds.put(name, value);
      return ':' + name;
    }
    return toLiteral(value);
  }

  /**
   * Formats a typed value as a SOQL/SOSL literal.
   * @param value String, Boolean, Decimal, Date or Datetime
   * @return the literal
   */
  @TestVisible
  private static String toLiteral(Object value) {
    if (value instanceof String) {
      return quote((String) value);
    }
    if (value instanceof Boolean) {
      return String.valueOf(value);
    }
    // Date before Datetime: in Apex a Date value is also "instanceof Datetime".
    if (value instanceof Date) {
      return String.valueOf((Date) value);
    }
    if (value instanceof Datetime) {
      return ((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }
    if (value instanceof Decimal) {
      // Covers Integer and Long too (both are "instanceof Decimal" in Apex). Going through
      // the string form avoids casting them, and toPlainString avoids exponent notation.
      return Decimal.valueOf(String.valueOf(value)).toPlainString();
    }
    throw new IllegalArgumentException(
      'Unsupported value type in query condition'
    );
  }

  /**
   * Quotes a string literal. Backslashes are escaped first, then single quotes, so a value
   * such as  a\' OR Name != '  stays inside its literal.
   * @param value the raw string
   * @return the quoted, escaped literal
   */
  @TestVisible
  private static String quote(String value) {
    return '\'' + value.replace('\\', '\\\\').replace('\'', '\\\'') + '\'';
  }

  /** One WHERE condition with typed values. Field names come from describe results only. */
  public class Condition {
    public String fieldName;
    public String operator;
    public List<Object> values;

    /**
     * Creates a condition.
     * @param fieldName canonical field API name from a describe result
     * @param operator one of = != > >= < IN INCLUDES
     * @param values typed values; one value except for IN and INCLUDES. A null value (only with
     *               = and !=) is written as the constant null.
     */
    public Condition(String fieldName, String operator, List<Object> values) {
      this.fieldName = fieldName;
      this.operator = operator;
      this.values = values;
    }
  }

  /** A SOQL query and its bind variables. */
  public class QuerySpec {
    public String query;
    public Map<String, Object> binds = new Map<String, Object>();
  }
}
