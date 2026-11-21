/**
 * Agentforce action: searches with a site search configuration and returns the best results
 * as text the agent can use, plus structured results.
 *
 * Security:
 * - with sharing, and SearchService runs every query in user mode, so results are limited to
 *   what the running user can see. For a service agent that is the dedicated agent user, not
 *   the person chatting (verified in the M9 spike, see docs/PROGRESS.md).
 * - Only configs with Allow_Agent_Access__c are used. An admin opts a config in once they're
 *   sure the agent user may share its results with anyone the agent talks to.
 * - All validation is SearchService's: the same allowlists, sanitizing and fail-closed filters
 *   as the site search.
 *
 * Errors don't throw: each response carries a Custom Label message in errorMessage, so the
 * agent can answer the person instead of failing the turn.
 *
 * Bulk: invocable methods receive a list. A search runs one SOSL query, plus one for a Knowledge
 * object with a data category. At most MAX_REQUESTS are searched per call, and only while at
 * least SOSL_PER_REQUEST queries are left in the transaction (the action may run after other
 * code); the rest get an error response. SearchService also stops before the limit, so the
 * uncatchable limit exception can't happen either way.
 */
public with sharing class SiteSearchAction {
  /** Results returned when maxResults isn't given. */
  @TestVisible
  private static final Integer DEFAULT_MAX_RESULTS = 5;

  /** Most results returned for one request. */
  @TestVisible
  private static final Integer MAX_RESULTS = 10;

  /** Most requests searched in one call. */
  @TestVisible
  private static final Integer MAX_REQUESTS = 10;

  /** SOSL queries one search may need: the shared query plus one Knowledge object with a category. */
  @TestVisible
  private static final Integer SOSL_PER_REQUEST = 2;

  @TestVisible
  private static SearchService service = new SearchService();

  @TestVisible
  private static SearchConfigProvider configProvider = new SearchConfigProvider();

  /**
   * Searches for each request.
   * @param requests one per search; at most MAX_REQUESTS are searched
   * @return one response per request, in the same order
   */
  @InvocableMethod(
    label='Search Site Content'
    description='Searches help articles and other records with a site search configuration and returns the best matches, best first. Use it to answer questions from existing content.'
    category='Site Search'
  )
  public static List<Response> search(List<Request> requests) {
    List<Response> responses = new List<Response>();
    if (requests == null) {
      return responses;
    }
    for (Integer i = 0; i < requests.size(); i++) {
      responses.add(
        i < MAX_REQUESTS && hasSoslBudget()
          ? searchOne(requests[i])
          : errorResponse(System.Label.Search_Agent_Too_Many)
      );
    }
    return responses;
  }

  private static Boolean hasSoslBudget() {
    return Limits.getLimitSoslQueries() - Limits.getSoslQueries() >=
      SOSL_PER_REQUEST;
  }

  private static Response searchOne(Request request) {
    try {
      if (request == null) {
        return errorResponse(System.Label.Search_Error_Invalid_Request);
      }
      SearchConfig config = configProvider.getActiveConfig(request.configName);
      if (!config.allowAgentAccess) {
        return errorResponse(System.Label.Search_Agent_Not_Allowed);
      }
      Integer maxResults = resolveMaxResults(request.maxResults);
      SearchRequestDto searchRequest = new SearchRequestDto();
      searchRequest.configName = config.developerName;
      searchRequest.searchTerm = request.searchTerm;
      searchRequest.limitPerObject = maxResults;
      searchRequest.selectedFacets = new List<SearchRequestDto.FacetSelection>();
      return toResponse(service.search(searchRequest), maxResults);
    } catch (SiteSearchException e) {
      return errorResponse(e.getMessage());
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'SiteSearch: agent search failed: ' +
          e.getTypeName() +
          ': ' +
          e.getMessage() +
          '\n' +
          e.getStackTraceString()
      );
      return errorResponse(System.Label.Search_Error_Generic);
    }
  }

  /**
   * maxResults if it is a positive number (capped at MAX_RESULTS), otherwise the default.
   * @param requested maxResults from the request (may be null)
   * @return results to return
   */
  @TestVisible
  private static Integer resolveMaxResults(Integer requested) {
    if (requested == null || requested < 1) {
      return DEFAULT_MAX_RESULTS;
    }
    return Math.min(requested, MAX_RESULTS);
  }

  /**
   * Builds the agent response: results from all objects mixed by rank (each object's best,
   * then each object's second best, ...), because boost scores of different objects aren't
   * comparable. Within an object the order is the site search's ranking.
   * @param searchResponse the search response
   * @param maxResults results to return at most
   * @return the response with summary text and structured results
   */
  @TestVisible
  private static Response toResponse(
    SearchResponseDto searchResponse,
    Integer maxResults
  ) {
    Response response = new Response();
    Integer rank = 0;
    Boolean more = true;
    while (more && response.results.size() < maxResults) {
      more = false;
      for (SearchResponseDto.ObjectGroup objectGroup : searchResponse.groups) {
        if (rank >= objectGroup.results.size()) {
          continue;
        }
        more = true;
        if (response.results.size() < maxResults) {
          response.results.add(
            toResult(objectGroup, objectGroup.results[rank])
          );
        }
      }
      rank++;
    }
    response.summary = summarize(searchResponse.searchTerm, response.results);
    return response;
  }

  private static Result toResult(
    SearchResponseDto.ObjectGroup objectGroup,
    SearchResponseDto.Result searchResult
  ) {
    Result result = new Result();
    result.recordId = searchResult.recordId;
    result.objectApiName = objectGroup.objectApiName;
    result.sectionLabel = objectGroup.sectionLabel;
    result.title = searchResult.title;
    List<String> details = new List<String>();
    for (SearchResponseDto.Detail detail : searchResult.details) {
      details.add(detail.label + ': ' + detail.value);
    }
    result.details = String.join(details, '; ');
    return result;
  }

  /**
   * Plain-text list of the results for the agent, one per line.
   * @param term the sanitized search term
   * @param results results in order
   * @return the summary
   */
  private static String summarize(String term, List<Result> results) {
    String shownTerm = term == null ? '' : term;
    if (results.isEmpty()) {
      return String.format(
        System.Label.Search_Agent_No_Results,
        new List<Object>{ shownTerm }
      );
    }
    List<String> lines = new List<String>{
      String.format(
        System.Label.Search_Agent_Summary,
        new List<Object>{ results.size(), shownTerm }
      )
    };
    for (Integer i = 0; i < results.size(); i++) {
      Result result = results[i];
      String line =
        (i + 1) +
        '. ' +
        result.title +
        ' (' +
        result.sectionLabel +
        ')';
      if (String.isNotBlank(result.details)) {
        line += ' - ' + result.details;
      }
      lines.add(line);
    }
    return String.join(lines, '\n');
  }

  private static Response errorResponse(String message) {
    Response response = new Response();
    response.errorMessage = message;
    response.summary = message;
    return response;
  }

  /** One search. */
  public class Request {
    @InvocableVariable(
      required=true
      label='Search Configuration'
      description='DeveloperName of an active Search Config that allows agent access, for example Support_Portal_Search.'
    )
    public String configName;

    @InvocableVariable(
      required=true
      label='Search Term'
      description='What to search for, in the words of the person asking, for example: reset password.'
    )
    public String searchTerm;

    @InvocableVariable(
      label='Maximum Results'
      description='How many results to return, 1 to 10. Default 5.'
    )
    public Integer maxResults;
  }

  /** The results of one search. */
  public class Response {
    @InvocableVariable(
      label='Summary'
      description='The results as a numbered list, best first, with each result\'s title, type and details. Or a message saying there are no results or why the search failed.'
    )
    public String summary;

    @InvocableVariable(label='Results' description='The results, best first.')
    public List<Result> results = new List<Result>();

    @InvocableVariable(
      label='Error Message'
      description='Set if the search could not run; explain it to the person instead of the results.'
    )
    public String errorMessage;
  }

  /** One result. Values are already formatted for display. */
  public class Result {
    @AuraEnabled
    @InvocableVariable(label='Record Id' description='Id of the record.')
    public Id recordId;

    @AuraEnabled
    @InvocableVariable(
      label='Object'
      description='API name of the record\'s object.'
    )
    public String objectApiName;

    @AuraEnabled
    @InvocableVariable(
      label='Type'
      description='The result group\'s label, for example Help Articles.'
    )
    public String sectionLabel;

    @AuraEnabled
    @InvocableVariable(label='Title' description='The record\'s title.')
    public String title;

    @AuraEnabled
    @InvocableVariable(
      label='Details'
      description='Detail fields as "Label: value", separated by semicolons.'
    )
    public String details;
  }
}
