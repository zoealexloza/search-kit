/**
 * Runs one search request end to end:
 *
 * 1. Load the active configuration (unknown or inactive configs are rejected).
 * 2. Validate every configured object and field against the schema for the running user.
 * 3. Narrow to the objects the request asks for (an object tab), if any, and validate the
 *    visitor's facet selections against those objects' facets.
 * 4. Term of 2+ characters after sanitizing: one SOSL query across the searched objects, plus
 *    one for each Knowledge object with a data category (see runSosl).
 *    No term but facets selected: one SOQL query per object that has a selection (browse).
 *    Neither: no query; only the facet definitions are returned.
 *    Knowledge objects always get "published only" and the language (KnowledgeSupport).
 * 5. Re-rank each object's results with its boost rules, then map to DTOs. Each query fetches a
 *    larger candidate pool than is shown (see candidateRowLimit), so a boosted record that SOSL
 *    ranks below the first page can still reach it.
 *
 * All queries run in USER_MODE, so object permissions, field-level security and sharing of the
 * running user (including guest users) are enforced by the platform, in addition to the checks
 * in SchemaValidator.
 */
public with sharing class SearchService {
  /** Highest limitPerObject a request may ask for ("Load more"). */
  @TestVisible
  private static final Integer MAX_LIMIT_PER_OBJECT = 200;

  /** Candidate pool per object, as a multiple of the number of results shown. */
  @TestVisible
  private static final Integer CANDIDATE_MULTIPLIER = 3;

  /** SOSL returns at most 2,000 rows per query, across all objects. */
  @TestVisible
  private static final Integer SOSL_MAX_ROWS = 2000;

  /** Most object names read from a request's objectApiNames (more than any config has). */
  @TestVisible
  private static final Integer MAX_SCOPE_NAMES = 20;

  private final SearchConfigProvider configProvider = new SearchConfigProvider();
  private final SchemaValidator validator = new SchemaValidator();
  private final FacetService facetService = new FacetService();

  /**
   * Runs a search.
   * @param request the request from the LWC
   * @return groups of ranked, formatted results plus facet definitions
   * @throws SiteSearchException if the request is missing or the config is unknown or inactive
   */
  public SearchResponseDto search(SearchRequestDto request) {
    if (request == null) {
      throw new SiteSearchException(System.Label.Search_Error_Invalid_Request);
    }
    SearchConfig config = configProvider.getActiveConfig(request.configName);
    List<SearchTarget> allTargets = validator.validateAll(config.objects);
    List<SearchTarget> targets = scopeTargets(
      allTargets,
      request.objectApiNames
    );
    setKnowledgeLanguages(targets, request.language);
    Map<String, Map<String, List<Object>>> selections = facetService.resolveSelections(
      targets,
      request.selectedFacets
    );

    SearchResponseDto response = new SearchResponseDto();
    response.objects = SearchResultMapper.toSearchableObjects(allTargets);
    response.facets = facetService.describeFacets(targets, selections);
    response.searchTerm = SearchQueryBuilder.sanitizeTerm(request.searchTerm);
    if (targets.isEmpty()) {
      return response;
    }

    Integer limitPerObject = resolveLimit(
      request.limitPerObject,
      config.resultsPerObject
    );
    Map<String, List<SearchQueryBuilder.Condition>> facetConditions = facetService.toConditions(
      targets,
      selections
    );
    Map<String, List<SObject>> rowsByObject;
    if (response.searchTerm.length() >= SearchQueryBuilder.MIN_TERM_LENGTH) {
      response.mode = SearchResponseDto.MODE_SEARCH;
      rowsByObject = runSosl(
        response.searchTerm,
        targets,
        facetConditions,
        limitPerObject
      );
    } else if (!facetConditions.isEmpty()) {
      response.mode = SearchResponseDto.MODE_BROWSE;
      rowsByObject = runBrowse(
        targets,
        facetConditions,
        candidateRowLimit(limitPerObject, 1)
      );
    } else {
      return response;
    }

    for (SearchTarget target : targets) {
      List<SObject> rows = rowsByObject.get(target.objectApiName.toLowerCase());
      if (rows == null || rows.isEmpty()) {
        continue;
      }
      Boolean hasMore = rows.size() > limitPerObject;
      // Rank everything fetched, then keep the best limitPerObject records.
      List<BoostRuleEngine.ScoredRecord> ranked = BoostRuleEngine.rank(
        rows,
        target.boostRules
      );
      while (ranked.size() > limitPerObject) {
        ranked.remove(ranked.size() - 1);
      }
      response.groups.add(SearchResultMapper.toGroup(target, ranked, hasMore));
    }
    return response;
  }

  /**
   * Narrows the search to the requested objects. The request is untrusted: names are only
   * matched (ignoring case) against targets that already passed validation, so an unknown,
   * inaccessible or malformed name can never add an object. At most MAX_SCOPE_NAMES names are
   * read.
   * @param targets validated targets, in config order
   * @param objectApiNames requested object API names (may be null)
   * @return the matching targets in config order; all targets if none was requested or matched
   */
  @TestVisible
  private static List<SearchTarget> scopeTargets(
    List<SearchTarget> targets,
    List<String> objectApiNames
  ) {
    Set<String> requested = new Set<String>();
    Integer nameCount = objectApiNames == null
      ? 0
      : Math.min(objectApiNames.size(), MAX_SCOPE_NAMES);
    for (Integer i = 0; i < nameCount; i++) {
      if (objectApiNames[i] != null) {
        requested.add(objectApiNames[i].toLowerCase());
      }
    }
    List<SearchTarget> scoped = new List<SearchTarget>();
    for (SearchTarget target : targets) {
      if (requested.contains(target.objectApiName.toLowerCase())) {
        scoped.add(target);
      }
    }
    return scoped.isEmpty() ? targets : scoped;
  }

  /**
   * Sets the language each Knowledge target is searched in for this request.
   * @param targets the targets being searched
   * @param requestedLanguage the visitor's site language from the request (untrusted, may be null)
   */
  private static void setKnowledgeLanguages(
    List<SearchTarget> targets,
    String requestedLanguage
  ) {
    for (SearchTarget target : targets) {
      if (target.isKnowledge) {
        target.knowledgeLanguage = KnowledgeSupport.resolveLanguage(
          target.languageField,
          requestedLanguage
        );
      }
    }
  }

  /**
   * Requested limit if it is a positive number (capped at MAX_LIMIT_PER_OBJECT), otherwise the
   * config's Results_Per_Object__c.
   * @param requested limitPerObject from the request (may be null)
   * @param configDefault Results_Per_Object__c from the config
   * @return the limit to use
   */
  @TestVisible
  private static Integer resolveLimit(
    Integer requested,
    Integer configDefault
  ) {
    if (requested == null || requested < 1) {
      return configDefault;
    }
    return Math.min(requested, MAX_LIMIT_PER_OBJECT);
  }

  /**
   * Rows to fetch per object: a candidate pool of CANDIDATE_MULTIPLIER x limitPerObject (at most
   * MAX_LIMIT_PER_OBJECT), plus one row that tells us whether there are more results. Boost rules
   * rank the whole pool before it is cut to limitPerObject, so a boosted record further down
   * SOSL's relevance order can still reach the first page.
   *
   * The pool shrinks so that objectCount x rows stays within SOSL_MAX_ROWS, but never below
   * limitPerObject + 1, which is the minimum needed to fill the page and detect "Load more".
   * @param limitPerObject results to show per object
   * @param objectCount objects in one query (SOSL: all targets; SOQL browse: 1)
   * @return LIMIT for each object
   */
  @TestVisible
  private static Integer candidateRowLimit(
    Integer limitPerObject,
    Integer objectCount
  ) {
    Integer pool = Math.max(
      Math.min(limitPerObject * CANDIDATE_MULTIPLIER, MAX_LIMIT_PER_OBJECT),
      limitPerObject
    );
    Integer budget = SOSL_MAX_ROWS / Math.max(objectCount, 1);
    return Math.max(Math.min(pool + 1, budget), limitPerObject + 1);
  }

  /**
   * Usually one SOSL query for all targets. WITH DATA CATEGORY applies to a whole SOSL query, so
   * each target with a data category (a Knowledge object; normally at most one per config) gets
   * its own query. Each query has its own 2,000-row budget. If the transaction runs out of SOSL
   * queries (an agent action running many searches), the remaining groups return nothing
   * rather than hitting the limit, which can't be caught.
   * @param term sanitized term
   * @param targets validated targets
   * @param facetConditions conditions per object (key: lower-case object API name)
   * @param limitPerObject results to show per object
   * @return lower-case object API name to rows
   */
  private static Map<String, List<SObject>> runSosl(
    String term,
    List<SearchTarget> targets,
    Map<String, List<SearchQueryBuilder.Condition>> facetConditions,
    Integer limitPerObject
  ) {
    List<SearchTarget> shared = new List<SearchTarget>();
    List<List<SearchTarget>> ownQuery = new List<List<SearchTarget>>();
    for (SearchTarget target : targets) {
      if (target.dataCategory == null) {
        shared.add(target);
      } else {
        ownQuery.add(new List<SearchTarget>{ target });
      }
    }
    List<List<SearchTarget>> queryGroups = new List<List<SearchTarget>>();
    if (!shared.isEmpty()) {
      queryGroups.add(shared);
    }
    queryGroups.addAll(ownQuery);
    Map<String, List<SObject>> rowsByObject = new Map<String, List<SObject>>();
    for (List<SearchTarget> queryGroup : queryGroups) {
      if (Limits.getSoslQueries() >= Limits.getLimitSoslQueries()) {
        break;
      }
      String sosl = SearchQueryBuilder.buildSosl(
        term,
        queryGroup,
        facetConditions,
        candidateRowLimit(limitPerObject, queryGroup.size())
      );
      List<List<SObject>> results = Search.query(sosl, AccessLevel.USER_MODE);
      for (Integer i = 0; i < queryGroup.size(); i++) {
        rowsByObject.put(queryGroup[i].objectApiName.toLowerCase(), results[i]);
      }
    }
    return rowsByObject;
  }

  /**
   * Browse mode needs one SOQL query per object (SOQL cannot query several objects at once).
   * Only objects with a facet selection are queried, so the count is bounded by the number of
   * objects in the configuration, far below the 100-query limit.
   * @param targets validated targets
   * @param facetConditions conditions per object (key: lower-case object API name)
   * @param rowLimit LIMIT per query
   * @return lower-case object API name to rows
   */
  private static Map<String, List<SObject>> runBrowse(
    List<SearchTarget> targets,
    Map<String, List<SearchQueryBuilder.Condition>> facetConditions,
    Integer rowLimit
  ) {
    Map<String, List<SObject>> rowsByObject = new Map<String, List<SObject>>();
    for (SearchTarget target : targets) {
      String objectKey = target.objectApiName.toLowerCase();
      // SOQL on Knowledge has no platform default language: without a valid language it would
      // return every language, so the object is left out instead (fail closed).
      if (target.isKnowledge && target.knowledgeLanguage == null) {
        continue;
      }
      if (facetConditions.containsKey(objectKey)) {
        rowsByObject.put(
          objectKey,
          queryObject(target, facetConditions, rowLimit)
        );
      }
    }
    return rowsByObject;
  }

  private static List<SObject> queryObject(
    SearchTarget target,
    Map<String, List<SearchQueryBuilder.Condition>> facetConditions,
    Integer rowLimit
  ) {
    SearchQueryBuilder.QuerySpec spec = SearchQueryBuilder.buildSoql(
      target,
      facetConditions,
      rowLimit
    );
    return Database.queryWithBinds(
      spec.query,
      spec.binds,
      AccessLevel.USER_MODE
    );
  }
}
