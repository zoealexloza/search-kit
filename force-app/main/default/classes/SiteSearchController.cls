/**
 * Apex entry point for the search components. Kept thin: delegates to SearchService and maps
 * exceptions to AuraHandledException. Only messages from Custom Labels reach the browser;
 * unexpected errors are logged and replaced with a generic message, so no internal details
 * (object names, query text, stack traces) leak to site visitors.
 */
public with sharing class SiteSearchController {
  /** Test seam: lets a test substitute a stub to simulate unexpected failures. */
  @TestVisible
  private static SearchService service;

  /**
   * Runs a search. Not cacheable: results depend on record data and the running user.
   * @param request search request from the LWC
   * @return ranked results grouped by object, plus facet definitions
   */
  @AuraEnabled
  public static SearchResponseDto search(SearchRequestDto request) {
    try {
      return (service != null ? service : new SearchService()).search(request);
    } catch (SiteSearchException e) {
      throw auraError(e.getMessage());
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'SiteSearch: search failed: ' +
          e.getTypeName() +
          ': ' +
          e.getMessage() +
          '\n' +
          e.getStackTraceString()
      );
      throw auraError(System.Label.Search_Error_Generic);
    }
  }

  private static AuraHandledException auraError(String message) {
    AuraHandledException error = new AuraHandledException(message);
    // Without setMessage, getMessage() returns "Script-thrown exception" in Apex tests.
    error.setMessage(message);
    return error;
  }
}
