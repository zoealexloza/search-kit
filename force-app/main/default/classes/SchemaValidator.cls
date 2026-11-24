/**
 * Checks search configuration against the schema, as seen by the running user, and turns each
 * SearchConfig.ObjectConfig into a SearchTarget.
 *
 * Invalid entries are skipped and logged rather than failing the whole search:
 * - object missing, inaccessible, or not searchable/queryable: the object is skipped
 * - title field invalid: the object is skipped (results would have no title)
 * - any filter rule invalid: the object is skipped. Filters restrict what visitors may see,
 *   so a broken filter must never be silently dropped (fail closed)
 * - Knowledge article object whose PublishStatus or Language field isn't readable, or whose
 *   data category is invalid or not visible to the running user: the object is skipped
 *   (fail closed, for the same reason)
 * - detail field, boost rule or facet invalid: only that entry is skipped. A lookup detail
 *   field shows the related record's name; if the running user can't read that name, the field
 *   is skipped too, so record IDs are never shown
 *
 * Validation is per running user: a field hidden by field-level security for a guest user is
 * skipped for that user only. This also keeps USER_MODE queries from failing on such fields.
 *
 * inherited sharing: uses describe calls only, no queries or DML.
 */
public inherited sharing class SchemaValidator {
  public static final String OP_EQUALS = 'equals';
  public static final String OP_NOT_EQUALS = 'not_equals';
  public static final String OP_INCLUDES = 'includes';
  public static final String OP_GREATER_THAN = 'greater_than';
  public static final String OP_LESS_THAN = 'less_than';
  public static final String OP_IS_TRUE = 'is_true';
  public static final String OP_IS_FALSE = 'is_false';
  public static final String OP_CONTAINS = 'contains';
  public static final String OP_IS_BLANK = 'is_blank';
  public static final String OP_IS_NOT_BLANK = 'is_not_blank';
  public static final String OP_IN = 'in';
  /**
   * Internal only, never configured (not in the operator sets below): greater_than with a
   * relative date on a Datetime field becomes "at or after the start of the next day".
   */
  public static final String OP_AT_OR_AFTER = 'at_or_after';

  /** Separates the values of an "in" rule, e.g. Billing;Account & Login. */
  public static final String VALUE_SEPARATOR = ';';

  private static final Set<String> FILTER_OPERATORS = new Set<String>{
    OP_EQUALS,
    OP_NOT_EQUALS,
    OP_INCLUDES,
    OP_GREATER_THAN,
    OP_LESS_THAN,
    OP_IS_TRUE,
    OP_IS_FALSE,
    OP_IS_BLANK,
    OP_IS_NOT_BLANK,
    OP_IN
  };
  private static final Set<String> BOOST_OPERATORS = new Set<String>{
    OP_EQUALS,
    OP_NOT_EQUALS,
    OP_INCLUDES,
    OP_GREATER_THAN,
    OP_LESS_THAN,
    OP_IS_TRUE,
    OP_IS_FALSE,
    OP_IS_BLANK,
    OP_IS_NOT_BLANK,
    OP_IN,
    OP_CONTAINS
  };
  /** Operators whose value may be a relative date (TODAY, LAST_N_DAYS:n, ...). */
  private static final Set<String> DATE_COMPARISONS = new Set<String>{
    OP_EQUALS,
    OP_NOT_EQUALS,
    OP_GREATER_THAN,
    OP_LESS_THAN
  };

  private static final Set<Schema.DisplayType> TEXT_TYPES = new Set<Schema.DisplayType>{
    Schema.DisplayType.STRING,
    Schema.DisplayType.TEXTAREA,
    Schema.DisplayType.EMAIL,
    Schema.DisplayType.PHONE,
    Schema.DisplayType.URL,
    Schema.DisplayType.COMBOBOX
  };
  private static final Set<Schema.DisplayType> NUMBER_TYPES = new Set<Schema.DisplayType>{
    Schema.DisplayType.DOUBLE,
    Schema.DisplayType.INTEGER,
    Schema.DisplayType.LONG,
    Schema.DisplayType.CURRENCY,
    Schema.DisplayType.PERCENT
  };
  private static final Set<Schema.DisplayType> ID_TYPES = new Set<Schema.DisplayType>{
    Schema.DisplayType.ID,
    Schema.DisplayType.REFERENCE
  };
  private static final Set<Schema.DisplayType> PICKLIST_TYPES = new Set<Schema.DisplayType>{
    Schema.DisplayType.PICKLIST,
    Schema.DisplayType.MULTIPICKLIST
  };
  private static final Set<Schema.DisplayType> DATE_TYPES = new Set<Schema.DisplayType>{
    Schema.DisplayType.DATE,
    Schema.DisplayType.DATETIME
  };
  private static final Set<Schema.DisplayType> FACET_TYPES = new Set<Schema.DisplayType>{
    Schema.DisplayType.PICKLIST,
    Schema.DisplayType.MULTIPICKLIST,
    Schema.DisplayType.BOOLEAN
  };

  // Letters, digits and underscores, starting with a letter. Rejects dots (relationship
  // paths), spaces, quotes and anything else before it can reach a describe call.
  private static final Pattern API_NAME = Pattern.compile(
    '^[A-Za-z][A-Za-z0-9_]{0,79}$'
  );
  private static final Pattern DATE_VALUE = Pattern.compile(
    '^\\d{4}-\\d{2}-\\d{2}$'
  );
  private static final Pattern DATETIME_VALUE = Pattern.compile(
    '^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d{1,3})?(Z|[+-]\\d{2}:\\d{2})$'
  );

  // Apex has no MIN_VALUE / MAX_VALUE constants on Integer and Long.
  private static final Decimal INTEGER_MIN = -2147483648L;
  private static final Decimal INTEGER_MAX = 2147483647L;
  private static final Decimal LONG_MIN = Decimal.valueOf(
    '-9223372036854775808'
  );
  private static final Decimal LONG_MAX = Decimal.valueOf(
    '9223372036854775807'
  );

  private final Map<String, Schema.DescribeSObjectResult> describeCache = new Map<String, Schema.DescribeSObjectResult>();
  /** Readable name field per related object, or null if there is none; for lookup details. */
  private final Map<Schema.SObjectType, Schema.DescribeFieldResult> nameFieldCache = new Map<Schema.SObjectType, Schema.DescribeFieldResult>();

  /**
   * Validates every object in a configuration, keeping config order.
   * @param objectConfigs objects from SearchConfig
   * @return targets that passed validation; invalid objects are left out
   */
  public List<SearchTarget> validateAll(
    List<SearchConfig.ObjectConfig> objectConfigs
  ) {
    List<SearchTarget> targets = new List<SearchTarget>();
    Set<String> seenObjects = new Set<String>();
    for (SearchConfig.ObjectConfig objectConfig : objectConfigs) {
      SearchTarget target = validate(objectConfig);
      if (target == null) {
        continue;
      }
      // SOSL cannot return the same object twice in one RETURNING clause.
      if (!seenObjects.add(target.objectApiName.toLowerCase())) {
        logSkip(
          objectConfig.developerName,
          'object ' +
            target.objectApiName +
            ' is already used by another Search Object in this config'
        );
        continue;
      }
      targets.add(target);
    }
    return targets;
  }

  /**
   * Validates one configured object for the running user.
   * @param objectConfig the object's configuration
   * @return the validated target, or null if the object cannot be searched
   */
  public SearchTarget validate(SearchConfig.ObjectConfig objectConfig) {
    Schema.DescribeSObjectResult objectDescribe = describeSearchableObject(
      objectConfig
    );
    if (objectDescribe == null) {
      return null;
    }
    SearchTarget target = new SearchTarget();
    target.objectApiName = objectDescribe.getName();
    target.objectDescribe = objectDescribe;
    target.sectionLabel = String.isNotBlank(objectConfig.sectionLabel)
      ? objectConfig.sectionLabel
      : objectDescribe.getLabelPlural();
    target.iconName = objectConfig.iconName;
    target.titleField = describeField(objectDescribe, objectConfig.titleField);
    if (target.titleField == null) {
      logSkip(
        objectConfig.developerName,
        'title field "' + objectConfig.titleField + '" is not a readable field'
      );
      return null;
    }
    if (!addFilterRules(target, objectConfig)) {
      return null;
    }
    if (!addKnowledgeSettings(target, objectConfig)) {
      return null;
    }
    addDetailFields(target, objectConfig);
    addBoostRules(target, objectConfig);
    addFacets(target, objectConfig);
    return target;
  }

  /**
   * Describes the configured object if the running user can access, search and query it.
   * @param objectConfig the object's configuration
   * @return the describe result, or null (logged) if the object cannot be used
   */
  private Schema.DescribeSObjectResult describeSearchableObject(
    SearchConfig.ObjectConfig objectConfig
  ) {
    Schema.DescribeSObjectResult objectDescribe = describeObject(
      objectConfig.objectApiName
    );
    if (objectDescribe == null) {
      logSkip(
        objectConfig.developerName,
        'object "' + objectConfig.objectApiName + '" does not exist'
      );
      return null;
    }
    if (
      !objectDescribe.isAccessible() ||
      !objectDescribe.isSearchable() ||
      !objectDescribe.isQueryable()
    ) {
      logSkip(
        objectConfig.developerName,
        'object ' +
          objectDescribe.getName() +
          ' is not accessible, searchable and queryable'
      );
      return null;
    }
    return objectDescribe;
  }

  /**
   * Adds validated filter rules to the target.
   * @param target the target being built
   * @param objectConfig the object's configuration
   * @return false if any filter rule is invalid; the object must then be skipped (fail closed)
   */
  private Boolean addFilterRules(
    SearchTarget target,
    SearchConfig.ObjectConfig objectConfig
  ) {
    for (SearchConfig.RuleConfig ruleConfig : objectConfig.filterRules) {
      SearchTarget.FieldRule rule = validateRule(
        target.objectDescribe,
        ruleConfig,
        true
      );
      if (rule == null) {
        logSkip(
          objectConfig.developerName,
          'filter rule ' +
            ruleConfig.developerName +
            ' is invalid, so the object is not searched'
        );
        return false;
      }
      target.filterRules.add(rule);
    }
    return true;
  }

  /**
   * For Knowledge article objects: the fields the service filters on must be readable, and a
   * configured data category must be valid and visible to the running user. Both restrict what
   * visitors see, so if either fails the object is skipped (fail closed), like a filter rule.
   * Data category fields on other objects are ignored.
   * @param target the target being built
   * @param objectConfig the object's configuration
   * @return false if the object must be skipped
   */
  private Boolean addKnowledgeSettings(
    SearchTarget target,
    SearchConfig.ObjectConfig objectConfig
  ) {
    if (!KnowledgeSupport.isKnowledgeObject(target.objectApiName)) {
      return true;
    }
    target.isKnowledge = true;
    target.publishStatusField = describeField(
      target.objectDescribe,
      KnowledgeSupport.PUBLISH_STATUS_FIELD
    );
    target.languageField = describeField(
      target.objectDescribe,
      KnowledgeSupport.LANGUAGE_FIELD
    );
    if (target.publishStatusField == null || target.languageField == null) {
      logSkip(
        objectConfig.developerName,
        'Knowledge fields PublishStatus and Language must be readable'
      );
      return false;
    }
    if (
      String.isBlank(objectConfig.dataCategoryGroup) &&
      String.isBlank(objectConfig.dataCategory)
    ) {
      return true;
    }
    target.dataCategory = KnowledgeSupport.validateCategory(
      objectConfig.dataCategoryGroup,
      objectConfig.dataCategory,
      objectConfig.dataCategoryOperator
    );
    if (target.dataCategory == null) {
      logSkip(
        objectConfig.developerName,
        'data category ' +
          objectConfig.dataCategoryGroup +
          ' / ' +
          objectConfig.dataCategory +
          ' is invalid or not visible to this user, so the object is not searched'
      );
      return false;
    }
    return true;
  }

  /**
   * Adds readable detail fields; invalid ones are skipped and logged. A lookup field is kept
   * only if the running user can read the related record's name, which is shown instead of
   * the ID.
   * @param target the target being built
   * @param objectConfig the object's configuration
   */
  private void addDetailFields(
    SearchTarget target,
    SearchConfig.ObjectConfig objectConfig
  ) {
    for (String detailFieldName : objectConfig.detailFields) {
      Schema.DescribeFieldResult detailField = describeField(
        target.objectDescribe,
        detailFieldName
      );
      if (detailField == null) {
        logSkip(
          objectConfig.developerName,
          'detail field "' + detailFieldName + '" is not a readable field'
        );
        continue;
      }
      if (detailField.getType() == Schema.DisplayType.REFERENCE) {
        SearchTarget.LookupName lookup = describeLookupName(detailField);
        if (lookup == null) {
          logSkip(
            objectConfig.developerName,
            'detail field "' +
              detailFieldName +
              '" is a lookup whose related record name is not readable'
          );
          continue;
        }
        target.lookupNames.put(detailField.getName().toLowerCase(), lookup);
      }
      target.detailFields.add(detailField);
    }
  }

  /**
   * Works out how to show a lookup field's related record name for the running user. Every
   * object the lookup can point to must be readable and have a readable name field: a
   * user-mode query that selects a relationship the user can't read fails as a whole.
   * @param field a lookup (REFERENCE) field
   * @return the name to select, or null if it can't be shown
   */
  @TestVisible
  private SearchTarget.LookupName describeLookupName(
    Schema.DescribeFieldResult field
  ) {
    List<Schema.SObjectType> relatedTypes = field.getReferenceTo();
    if (String.isBlank(field.getRelationshipName()) || relatedTypes.isEmpty()) {
      return null;
    }
    String nameField;
    for (Schema.SObjectType relatedType : relatedTypes) {
      Schema.DescribeFieldResult relatedName = readableNameField(relatedType);
      if (relatedName == null) {
        return null;
      }
      nameField = relatedName.getName();
    }
    SearchTarget.LookupName lookup = new SearchTarget.LookupName();
    lookup.relationshipName = field.getRelationshipName();
    // A polymorphic lookup (OwnerId: user or queue) is queried through the Name object, whose
    // name field is always Name.
    lookup.nameField = field.isNamePointing() ? 'Name' : nameField;
    lookup.label = lookupLabel(field);
    return lookup;
  }

  /**
   * Finds an object's name field (Name, CaseNumber, Title...) if the running user can read the
   * object and that field.
   * @param objectType the related object
   * @return the name field, or null
   */
  private Schema.DescribeFieldResult readableNameField(
    Schema.SObjectType objectType
  ) {
    if (nameFieldCache.containsKey(objectType)) {
      return nameFieldCache.get(objectType);
    }
    Schema.DescribeFieldResult nameField;
    Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe(
      SObjectDescribeOptions.DEFERRED
    );
    if (objectDescribe.isAccessible()) {
      for (
        Schema.SObjectField token : objectDescribe.fields.getMap().values()
      ) {
        Schema.DescribeFieldResult candidate = token.getDescribe();
        if (candidate.isNameField()) {
          nameField = candidate.isAccessible() ? candidate : null;
          break;
        }
      }
    }
    nameFieldCache.put(objectType, nameField);
    return nameField;
  }

  /**
   * Label for a lookup detail. Standard lookups are labelled like "Account ID" or "Owner ID";
   * the value shown is a name, so the " ID" suffix is dropped. Custom lookup labels are the
   * admin's own and kept as they are.
   * @param field a lookup field
   * @return the label to show
   */
  @TestVisible
  private static String lookupLabel(Schema.DescribeFieldResult field) {
    String label = field.getLabel();
    if (!field.isCustom() && label.length() > 3 && label.endsWith(' ID')) {
      return label.removeEnd(' ID');
    }
    return label;
  }

  /**
   * Adds valid boost rules; invalid ones are skipped and logged.
   * @param target the target being built
   * @param objectConfig the object's configuration
   */
  private void addBoostRules(
    SearchTarget target,
    SearchConfig.ObjectConfig objectConfig
  ) {
    for (SearchConfig.RuleConfig ruleConfig : objectConfig.boostRules) {
      SearchTarget.FieldRule rule = validateRule(
        target.objectDescribe,
        ruleConfig,
        false
      );
      if (rule == null) {
        logSkip(ruleConfig.developerName, 'boost rule is invalid');
      } else {
        target.boostRules.add(rule);
      }
    }
  }

  /**
   * Adds valid facets; invalid or duplicate ones are skipped and logged.
   * @param target the target being built
   * @param objectConfig the object's configuration
   */
  private void addFacets(
    SearchTarget target,
    SearchConfig.ObjectConfig objectConfig
  ) {
    for (SearchConfig.FacetConfig facetConfig : objectConfig.facets) {
      SearchTarget.Facet facet = validateFacet(
        target.objectDescribe,
        facetConfig
      );
      if (facet == null) {
        logSkip(
          facetConfig.developerName,
          'facet field "' +
            facetConfig.fieldApiName +
            '" must be a readable, filterable picklist, multi-select picklist or checkbox'
        );
      } else if (target.findFacet(facet.field.getName()) != null) {
        logSkip(
          facetConfig.developerName,
          'another facet already uses field ' + facet.field.getName()
        );
      } else {
        target.facets.add(facet);
      }
    }
  }

  /**
   * Describes an object by API name.
   * @param objectApiName object API name, any case
   * @return the describe result, or null if the name is malformed or the object does not exist
   */
  public Schema.DescribeSObjectResult describeObject(String objectApiName) {
    if (!isApiName(objectApiName)) {
      return null;
    }
    String key = objectApiName.toLowerCase();
    if (!describeCache.containsKey(key)) {
      Schema.DescribeSObjectResult result = null;
      try {
        result = Schema.describeSObjects(
          new List<String>{ objectApiName },
          SObjectDescribeOptions.DEFERRED
        )[0];
      } catch (InvalidParameterValueException e) {
        // Unknown object name: leave result null.
        System.debug(
          LoggingLevel.FINE,
          'SiteSearch: unknown object ' + objectApiName
        );
      } catch (NoAccessException e) {
        // Some objects (e.g. Knowledge article versions) can't even be described by a user
        // without access to them. Treat them like an unknown object, so only this object is
        // skipped and the rest of the search still runs.
        System.debug(
          LoggingLevel.FINE,
          'SiteSearch: no access to object ' + objectApiName
        );
      }
      describeCache.put(key, result);
    }
    return describeCache.get(key);
  }

  /**
   * Describes a field the running user can read.
   * @param objectDescribe the object the field belongs to
   * @param fieldApiName field API name, any case
   * @return the describe result, or null if malformed, missing, or not readable
   */
  public Schema.DescribeFieldResult describeField(
    Schema.DescribeSObjectResult objectDescribe,
    String fieldApiName
  ) {
    if (!isApiName(fieldApiName)) {
      return null;
    }
    Schema.SObjectField token = objectDescribe.fields.getMap()
      .get(fieldApiName);
    if (token == null) {
      return null;
    }
    Schema.DescribeFieldResult field = token.getDescribe();
    return field.isAccessible() ? field : null;
  }

  /**
   * Validates a rule and converts its value to the field's type.
   * @param objectDescribe the object the rule's field belongs to
   * @param ruleConfig the rule as configured
   * @param isFilter true for filter rules (run in the query, so the field must be filterable),
   *                 false for boost rules (evaluated in Apex, and may also use contains)
   * @return the validated rule, or null if it is invalid
   */
  @TestVisible
  private SearchTarget.FieldRule validateRule(
    Schema.DescribeSObjectResult objectDescribe,
    SearchConfig.RuleConfig ruleConfig,
    Boolean isFilter
  ) {
    String operator = normalizeOperator(ruleConfig.operator, isFilter);
    if (operator == null) {
      return null;
    }
    Schema.DescribeFieldResult field = describeField(
      objectDescribe,
      ruleConfig.fieldApiName
    );
    if (field == null || (isFilter && !field.isFilterable())) {
      return null;
    }
    SearchTarget.FieldRule rule = new SearchTarget.FieldRule();
    rule.developerName = ruleConfig.developerName;
    rule.field = field;
    rule.operator = operator;
    rule.points = ruleConfig.points == null ? 0 : ruleConfig.points;
    return applyValue(rule, ruleConfig.value) ? rule : null;
  }

  /**
   * Lower-cases a configured operator and checks it against the allowed set.
   * @param operator the configured operator
   * @param isFilter true for filter rules, false for boost rules (which also allow contains)
   * @return the lower-case operator, or null if it is missing or not allowed
   */
  private static String normalizeOperator(String operator, Boolean isFilter) {
    if (operator == null) {
      return null;
    }
    String normalized = operator.trim().toLowerCase();
    Set<String> allowed = isFilter ? FILTER_OPERATORS : BOOST_OPERATORS;
    return allowed.contains(normalized) ? normalized : null;
  }

  /**
   * Checks that the rule's operator suits its field type and sets the typed value.
   * @param rule the rule being built (field and lower-case operator set)
   * @param rawValue the configured value
   * @return false if the combination is not allowed or the value is invalid
   */
  private static Boolean applyValue(
    SearchTarget.FieldRule rule,
    String rawValue
  ) {
    Schema.DisplayType fieldType = rule.field.getType();
    if (rule.operator == OP_IS_BLANK || rule.operator == OP_IS_NOT_BLANK) {
      // No value to compare. Checkboxes are never blank, so the rule would be meaningless.
      return isBlankable(fieldType);
    }
    Date relativeDay = DATE_TYPES.contains(fieldType) &&
      DATE_COMPARISONS.contains(rule.operator)
      ? RelativeDateParser.resolve(rawValue)
      : null;
    if (relativeDay != null) {
      return applyRelativeDay(rule, relativeDay);
    }
    rule.value = parseRuleValue(rule.field, rule.operator, rawValue);
    return rule.value != null;
  }

  /**
   * Sets a relative date rule's value (and, for Datetime fields, its comparison). A Date field
   * compares with the day itself. A Datetime field compares with day boundaries in the running
   * user's time zone, so the same rule selects the same days on both field types:
   * greater_than day means at or after the start of the next day, less_than day means before the
   * start of the day. equals / not_equals on a Datetime field would need a range (two
   * conditions), so they are not allowed with relative dates.
   * @param rule the rule being built; its field is a Date or Datetime field
   * @param day the resolved day
   * @return false if the operator cannot be used with a relative date on this field
   */
  private static Boolean applyRelativeDay(
    SearchTarget.FieldRule rule,
    Date day
  ) {
    if (rule.field.getType() == Schema.DisplayType.DATE) {
      rule.value = day;
      return true;
    }
    if (rule.operator == OP_GREATER_THAN) {
      rule.operator = OP_AT_OR_AFTER;
      rule.value = RelativeDateParser.startOfDay(day.addDays(1));
      return true;
    }
    if (rule.operator == OP_LESS_THAN) {
      rule.value = RelativeDateParser.startOfDay(day);
      return true;
    }
    return false;
  }

  /**
   * Whether is_blank / is_not_blank can be used on a field type: every type a rule value can
   * have except checkbox.
   * @param fieldType the field's type
   * @return true if the field can be blank
   */
  private static Boolean isBlankable(Schema.DisplayType fieldType) {
    return TEXT_TYPES.contains(fieldType) ||
      PICKLIST_TYPES.contains(fieldType) ||
      NUMBER_TYPES.contains(fieldType) ||
      DATE_TYPES.contains(fieldType) ||
      ID_TYPES.contains(fieldType);
  }

  /**
   * Splits and converts the value of an "in" rule. Every value must be valid for the field;
   * one invalid value makes the whole rule invalid, so a typo is never silently dropped.
   * Empty parts (a trailing ;) are ignored and duplicates removed.
   * @param field a text, picklist, multi-select picklist, number or Id field
   * @param rawValue values separated by VALUE_SEPARATOR
   * @return the typed values in configured order, or null if any value is invalid or none is given
   */
  private static List<Object> parseValueList(
    Schema.DescribeFieldResult field,
    String rawValue
  ) {
    if (String.isBlank(rawValue)) {
      return null;
    }
    List<Object> values = new List<Object>();
    Set<String> seen = new Set<String>();
    for (String part : rawValue.split(VALUE_SEPARATOR)) {
      if (String.isBlank(part)) {
        continue;
      }
      Object value = parseTypedValue(field, part);
      if (value == null) {
        return null;
      }
      if (seen.add(String.valueOf(value).toLowerCase())) {
        values.add(value);
      }
    }
    return values.isEmpty() ? null : values;
  }

  /**
   * Checks that an operator suits the field type and converts the configured value.
   * Relative dates and is_blank / is_not_blank are handled in applyValue.
   * @param field the rule's field
   * @param operator lower-case operator
   * @param rawValue the configured value
   * @return the typed value (a List<Object> for in), or null if the combination is not allowed
   *         or the value is invalid
   */
  private static Object parseRuleValue(
    Schema.DescribeFieldResult field,
    String operator,
    String rawValue
  ) {
    Schema.DisplayType fieldType = field.getType();
    if (operator == OP_IN) {
      // Booleans have two values (use equals); dates are compared, not listed.
      Boolean listable =
        TEXT_TYPES.contains(fieldType) ||
        PICKLIST_TYPES.contains(fieldType) ||
        NUMBER_TYPES.contains(fieldType) ||
        ID_TYPES.contains(fieldType);
      return listable ? parseValueList(field, rawValue) : null;
    }
    if (operator == OP_IS_TRUE || operator == OP_IS_FALSE) {
      return fieldType == Schema.DisplayType.BOOLEAN
        ? operator == OP_IS_TRUE
        : null;
    }
    if (operator == OP_INCLUDES) {
      return fieldType == Schema.DisplayType.MULTIPICKLIST
        ? canonicalPicklistValue(field, rawValue)
        : null;
    }
    if (operator == OP_CONTAINS) {
      Boolean textLike =
        TEXT_TYPES.contains(fieldType) ||
        fieldType == Schema.DisplayType.PICKLIST ||
        fieldType == Schema.DisplayType.MULTIPICKLIST;
      return textLike && String.isNotBlank(rawValue) ? rawValue.trim() : null;
    }
    if (operator == OP_GREATER_THAN || operator == OP_LESS_THAN) {
      Boolean ordered =
        NUMBER_TYPES.contains(fieldType) ||
        fieldType == Schema.DisplayType.DATE ||
        fieldType == Schema.DisplayType.DATETIME;
      return ordered ? parseTypedValue(field, rawValue) : null;
    }
    // equals / not_equals. A multi-select picklist "equals" means "exactly this set of
    // values", which is rarely what an admin means, so includes is required instead.
    return fieldType == Schema.DisplayType.MULTIPICKLIST
      ? null
      : parseTypedValue(field, rawValue);
  }

  /**
   * Converts a configured or requested value to the field's type.
   * @param field the field the value is compared with
   * @param rawValue the value as text
   * @return String, Boolean, Decimal, Date or Datetime; null if the value is invalid for the
   *         field type or the type is not supported
   */
  public static Object parseTypedValue(
    Schema.DescribeFieldResult field,
    String rawValue
  ) {
    if (String.isBlank(rawValue)) {
      return null;
    }
    String value = rawValue.trim();
    Schema.DisplayType fieldType = field.getType();
    if (
      fieldType == Schema.DisplayType.PICKLIST ||
      fieldType == Schema.DisplayType.MULTIPICKLIST
    ) {
      return canonicalPicklistValue(field, value);
    }
    if (TEXT_TYPES.contains(fieldType)) {
      return value;
    }
    if (fieldType == Schema.DisplayType.BOOLEAN) {
      return parseBoolean(value);
    }
    if (ID_TYPES.contains(fieldType)) {
      return parseId(value);
    }
    if (
      fieldType == Schema.DisplayType.INTEGER ||
      fieldType == Schema.DisplayType.LONG
    ) {
      // Database.queryWithBinds rejects a Decimal bound to an Integer column, so whole-number
      // fields get Integer/Long values (verified in a scratch org, see docs/PROGRESS.md).
      return parseWholeNumber(value, fieldType == Schema.DisplayType.INTEGER);
    }
    if (NUMBER_TYPES.contains(fieldType)) {
      return parseDecimal(value);
    }
    if (fieldType == Schema.DisplayType.DATE) {
      return parseDate(value);
    }
    if (fieldType == Schema.DisplayType.DATETIME) {
      return parseDatetime(value);
    }
    return null;
  }

  /**
   * Matches a value against the field's active picklist values, ignoring case (as SOQL does).
   * @param field a picklist or multi-select picklist field
   * @param rawValue a single picklist value
   * @return the value as defined in the picklist, or null if it is not an active value
   */
  public static String canonicalPicklistValue(
    Schema.DescribeFieldResult field,
    String rawValue
  ) {
    if (String.isBlank(rawValue)) {
      return null;
    }
    String value = rawValue.trim();
    for (Schema.PicklistEntry entry : field.getPicklistValues()) {
      if (entry.isActive() && entry.getValue().equalsIgnoreCase(value)) {
        return entry.getValue();
      }
    }
    return null;
  }

  /**
   * Whether a field can be used as a facet in v1.
   * @param field the field
   * @return true for picklist, multi-select picklist and checkbox fields
   */
  public static Boolean isFacetType(Schema.DescribeFieldResult field) {
    return FACET_TYPES.contains(field.getType());
  }

  private SearchTarget.Facet validateFacet(
    Schema.DescribeSObjectResult objectDescribe,
    SearchConfig.FacetConfig facetConfig
  ) {
    Schema.DescribeFieldResult field = describeField(
      objectDescribe,
      facetConfig.fieldApiName
    );
    if (field == null || !isFacetType(field) || !field.isFilterable()) {
      return null;
    }
    SearchTarget.Facet facet = new SearchTarget.Facet();
    facet.field = field;
    facet.label = String.isNotBlank(facetConfig.label)
      ? facetConfig.label
      : field.getLabel();
    return facet;
  }

  private static Boolean isApiName(String name) {
    return name != null && API_NAME.matcher(name).matches();
  }

  private static Boolean parseBoolean(String value) {
    if (value.equalsIgnoreCase('true')) {
      return true;
    }
    if (value.equalsIgnoreCase('false')) {
      return false;
    }
    return null;
  }

  private static String parseId(String value) {
    try {
      return String.valueOf(Id.valueOf(value));
    } catch (StringException e) {
      return null;
    }
  }

  private static Decimal parseDecimal(String value) {
    try {
      return Decimal.valueOf(value);
    } catch (TypeException e) {
      return null;
    }
  }

  /**
   * Parses a whole number for an Integer or Long field.
   * @param value the value as text
   * @param asInteger true for Integer fields, false for Long fields
   * @return Integer or Long; null if not a whole number or out of range
   */
  private static Object parseWholeNumber(String value, Boolean asInteger) {
    Decimal parsed = parseDecimal(value);
    if (parsed == null || parsed != parsed.round(System.RoundingMode.DOWN)) {
      return null;
    }
    if (asInteger) {
      return parsed >= INTEGER_MIN &&
        parsed <= INTEGER_MAX
        ? (Object) parsed.intValue()
        : null;
    }
    return parsed >= LONG_MIN &&
      parsed <= LONG_MAX
      ? (Object) parsed.longValue()
      : null;
  }

  private static Date parseDate(String value) {
    if (!DATE_VALUE.matcher(value).matches()) {
      return null;
    }
    try {
      return Date.valueOf(value);
    } catch (TypeException e) {
      return null;
    }
  }

  private static Datetime parseDatetime(String value) {
    if (!DATETIME_VALUE.matcher(value).matches()) {
      return null;
    }
    try {
      // The pattern above guarantees value contains no quotes, so it is safe in JSON.
      return (Datetime) JSON.deserialize('"' + value + '"', Datetime.class);
    } catch (JSONException e) {
      return null;
    }
  }

  private static void logSkip(String entryName, String reason) {
    System.debug(
      LoggingLevel.WARN,
      'SiteSearch: skipped ' + entryName + ': ' + reason
    );
  }
}
