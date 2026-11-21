import { createElement } from "lwc";
import SearchResults, {
  appendResults,
  formatLabel,
  MAX_LIMIT_PER_OBJECT,
  parseObjectParam,
  parseSelections,
  serializeSelections
} from "c/searchResults";
import { facetKey } from "c/searchFacets";
import {
  CurrentPageReference,
  getNavigateCalls,
  resetNavigationMock
} from "lightning/navigation";
import search from "@salesforce/apex/SiteSearchController.search";

jest.mock(
  "@salesforce/apex/SiteSearchController.search",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

// The visitor's site language, sent with every request for Knowledge articles.
jest.mock("@salesforce/i18n/lang", () => ({ default: "es-MX" }), {
  virtual: true
});

// Real label text for the labels whose placeholders the tests check.
jest.mock(
  "@salesforce/label/c.Search_Results_None",
  () => ({ default: 'No results for "{0}".' }),
  { virtual: true }
);
jest.mock(
  "@salesforce/label/c.Search_Results_Count_One",
  () => ({ default: '1 result for "{0}"' }),
  { virtual: true }
);
jest.mock(
  "@salesforce/label/c.Search_Results_Count_Many",
  () => ({ default: '{0} results for "{1}"' }),
  { virtual: true }
);
jest.mock(
  "@salesforce/label/c.Search_Results_None_Filtered",
  () => ({ default: 'No results for "{0}" with the selected filters.' }),
  { virtual: true }
);
jest.mock(
  "@salesforce/label/c.Search_Results_Count_Browse_Many",
  () => ({ default: "{0} results" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/label/c.Search_Results_Load_More",
  () => ({ default: "Load more {0}" }),
  { virtual: true }
);

const RESPONSE = {
  searchTerm: "password",
  mode: "search",
  facets: [],
  groups: [
    {
      objectApiName: "Help_Article__c",
      sectionLabel: "Help Articles",
      iconName: "standard:article",
      totalShown: 2,
      hasMore: false,
      results: [
        {
          recordId: "a00000000000001AAA",
          title: "Your first login",
          score: 61,
          details: [{ label: "Category", value: "Getting Started" }]
        },
        {
          recordId: "a00000000000002AAA",
          title: "Reset your password",
          score: 4,
          details: []
        }
      ]
    },
    {
      objectApiName: "Case",
      sectionLabel: "Cases",
      iconName: null,
      totalShown: 1,
      hasMore: false,
      results: [
        {
          recordId: "500000000000001AAA",
          title: "Password reset email never arrived",
          score: 1,
          details: []
        }
      ]
    }
  ]
};

/** Resolves every pending promise (Apex call, re-render). */
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function createResults(configName = "Support_Portal_Search") {
  const element = createElement("c-search-results", { is: SearchResults });
  element.configName = configName;
  document.body.appendChild(element);
  return element;
}

async function showTerm(element, term) {
  CurrentPageReference.emit({ state: term === undefined ? {} : { term } });
  await flushPromises();
}

const statusText = (element) =>
  element.shadowRoot.querySelector('[role="status"]').textContent.trim();

describe("c-search-results", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("calls Apex with the config and the term from the URL", async () => {
    search.mockResolvedValue(RESPONSE);
    const element = createResults();
    await showTerm(element, "  password ");

    expect(search).toHaveBeenCalledTimes(1);
    expect(search).toHaveBeenCalledWith({
      request: {
        configName: "Support_Portal_Search",
        searchTerm: "password",
        selectedFacets: [],
        limitPerObject: null,
        language: "es-MX"
      }
    });
  });

  it("renders results grouped by object, in server order", async () => {
    search.mockResolvedValue(RESPONSE);
    const element = createResults();
    await showTerm(element, "password");

    const headings = [...element.shadowRoot.querySelectorAll("h3")].map(
      (node) => node.textContent.trim()
    );
    expect(headings).toEqual(["Help Articles", "Cases"]);

    const cards = element.shadowRoot.querySelectorAll("c-search-result-card");
    expect(cards).toHaveLength(3);
    expect(cards[0].result.title).toBe("Your first login");
    expect(cards[0].objectApiName).toBe("Help_Article__c");
    expect(cards[2].objectApiName).toBe("Case");
  });

  it("shows the group icon only when one is configured", async () => {
    search.mockResolvedValue(RESPONSE);
    const element = createResults();
    await showTerm(element, "password");

    const icons = element.shadowRoot.querySelectorAll("lightning-icon");
    expect(icons).toHaveLength(1);
    expect(icons[0].iconName).toBe("standard:article");
  });

  it("announces the result count in the live region", async () => {
    search.mockResolvedValue(RESPONSE);
    const element = createResults();
    await showTerm(element, "password");

    expect(statusText(element)).toBe('3 results for "password"');
  });

  it("uses the singular message for one result", async () => {
    search.mockResolvedValue({
      ...RESPONSE,
      groups: [{ ...RESPONSE.groups[1] }]
    });
    const element = createResults();
    await showTerm(element, "password");

    expect(statusText(element)).toBe('1 result for "password"');
  });

  it("shows the sanitized term the server searched for", async () => {
    search.mockResolvedValue({ ...RESPONSE, searchTerm: "pass word" });
    const element = createResults();
    await showTerm(element, "pass*word");

    expect(statusText(element)).toBe('3 results for "pass word"');
  });

  it("shows an empty state when nothing matches", async () => {
    search.mockResolvedValue({
      searchTerm: "zzz",
      mode: "search",
      groups: [],
      facets: []
    });
    const element = createResults();
    await showTerm(element, "zzz");

    expect(statusText(element)).toBe('No results for "zzz".');
    expect(element.shadowRoot.querySelector("c-search-result-card")).toBeNull();
  });

  it("asks for a longer term when the server ran no query", async () => {
    search.mockResolvedValue({
      searchTerm: "a",
      mode: "none",
      groups: [],
      facets: []
    });
    const element = createResults();
    await showTerm(element, "a");

    expect(statusText(element)).toBe("c.Search_Results_Term_Too_Short");
  });

  it("shows no results, not 'too short', when no object is searchable", async () => {
    // e.g. a guest user who can't read any configured object: the server runs no query.
    search.mockResolvedValue({
      searchTerm: "password",
      mode: "none",
      groups: [],
      facets: []
    });
    const element = createResults();
    await showTerm(element, "password");

    expect(statusText(element)).toBe('No results for "password".');
  });

  it("treats a term the server shortened below 2 characters as too short", async () => {
    search.mockResolvedValue({
      searchTerm: "",
      mode: "none",
      groups: [],
      facets: []
    });
    const element = createResults();
    await showTerm(element, "*?");

    expect(statusText(element)).toBe("c.Search_Results_Term_Too_Short");
  });

  it("prompts for a term and skips Apex when the URL has none", async () => {
    const element = createResults();
    await showTerm(element, undefined);

    expect(search).not.toHaveBeenCalled();
    expect(statusText(element)).toBe("c.Search_Results_Prompt");
  });

  it("shows a spinner and marks the region busy while loading", async () => {
    let resolveSearch;
    search.mockReturnValue(
      new Promise((resolve) => {
        resolveSearch = resolve;
      })
    );
    const element = createResults();
    await showTerm(element, "password");

    const region = element.shadowRoot.querySelector("section");
    expect(
      element.shadowRoot.querySelector("lightning-spinner")
    ).not.toBeNull();
    expect(region.getAttribute("aria-busy")).toBe("true");
    expect(statusText(element)).toBe("c.Search_Results_Loading");

    resolveSearch(RESPONSE);
    await flushPromises();
    expect(element.shadowRoot.querySelector("lightning-spinner")).toBeNull();
    expect(region.getAttribute("aria-busy")).toBe("false");
  });

  it("shows the server's error message", async () => {
    search.mockRejectedValue({
      body: { message: "Search isn't set up correctly." }
    });
    const element = createResults();
    await showTerm(element, "password");

    const alert = element.shadowRoot.querySelector('[role="alert"]');
    expect(alert.textContent.trim()).toBe("Search isn't set up correctly.");
    expect(element.shadowRoot.querySelector("c-search-result-card")).toBeNull();
  });

  it("falls back to a generic error when the error has no message", async () => {
    search.mockRejectedValue(new Error("network"));
    const element = createResults();
    await showTerm(element, "password");

    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent.trim()
    ).toBe("c.Search_Error_Generic");
  });

  it("shows a setup error without calling Apex when no config is chosen", async () => {
    const element = createResults("");
    await showTerm(element, "password");

    expect(search).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent.trim()
    ).toBe("c.Search_Error_Config_Not_Found");
  });

  it("searches again when the term in the URL changes", async () => {
    search.mockResolvedValue(RESPONSE);
    const element = createResults();
    await showTerm(element, "password");
    await showTerm(element, "invoice");

    expect(search).toHaveBeenCalledTimes(2);
    expect(search.mock.calls[1][0].request.searchTerm).toBe("invoice");
  });

  it("does not search again when the page reference repeats the same term", async () => {
    search.mockResolvedValue(RESPONSE);
    const element = createResults();
    await showTerm(element, "password");
    await showTerm(element, "password");

    expect(search).toHaveBeenCalledTimes(1);
  });

  it("ignores a slow response that a newer search replaced", async () => {
    let resolveFirst;
    search
      .mockReturnValueOnce(
        new Promise((resolve) => {
          resolveFirst = resolve;
        })
      )
      .mockResolvedValueOnce({
        searchTerm: "invoice",
        mode: "search",
        groups: [],
        facets: []
      });
    const element = createResults();
    await showTerm(element, "password");
    await showTerm(element, "invoice");

    resolveFirst(RESPONSE);
    await flushPromises();

    expect(statusText(element)).toBe('No results for "invoice".');
    expect(element.shadowRoot.querySelector("c-search-result-card")).toBeNull();
  });

  it("is accessible with results", async () => {
    search.mockResolvedValue(RESPONSE);
    const element = createResults();
    await showTerm(element, "password");
    await expect(element).toBeAccessible();
  });

  it("is accessible in the error state", async () => {
    search.mockRejectedValue({ body: { message: "Something went wrong." } });
    const element = createResults();
    await showTerm(element, "password");
    await expect(element).toBeAccessible();
  });
});

const FACETS = [
  {
    objectApiName: "Help_Article__c",
    fieldApiName: "Category__c",
    label: "Category",
    values: [
      { value: "Getting Started", label: "Getting Started", selected: false },
      { value: "Billing", label: "Billing", selected: false }
    ]
  },
  {
    objectApiName: "Help_Article__c",
    fieldApiName: "Featured__c",
    label: "Featured",
    values: [
      { value: "true", label: "Yes", selected: false },
      { value: "false", label: "No", selected: false }
    ]
  }
];

/** Builds an article group with `count` results. */
function articleGroup(count, hasMore) {
  const results = Array.from({ length: count }, (_, i) => ({
    recordId: `a0000000000${String(i).padStart(4, "0")}AAA`,
    title: `Article ${i + 1}`,
    score: count - i,
    details: []
  }));
  return {
    objectApiName: "Help_Article__c",
    sectionLabel: "Help Articles",
    iconName: "standard:article",
    totalShown: count,
    hasMore,
    results
  };
}

const NO_TERM = { searchTerm: "", mode: "none", groups: [], facets: FACETS };

const BROWSE = {
  searchTerm: "",
  mode: "browse",
  groups: [articleGroup(3, false)],
  facets: FACETS
};

function createWithFacets(showFacets = true) {
  const element = createElement("c-search-results", { is: SearchResults });
  element.configName = "Support_Portal_Search";
  element.showFacets = showFacets;
  document.body.appendChild(element);
  return element;
}

const facetPanel = (element) =>
  element.shadowRoot.querySelector("c-search-facets");

async function changeFacet(element, fieldApiName, values) {
  facetPanel(element).dispatchEvent(
    new CustomEvent("facetchange", {
      detail: { objectApiName: "Help_Article__c", fieldApiName, values }
    })
  );
  await flushPromises();
}

const lastRequest = () => search.mock.calls.at(-1)[0].request;

const loadMoreButton = (element) =>
  element.shadowRoot.querySelector(
    'lightning-button[data-object-api-name="Help_Article__c"]'
  );

describe("c-search-results facets and browse mode", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("loads facet definitions without a term when the panel is shown", async () => {
    search.mockResolvedValue(NO_TERM);
    const element = createWithFacets();
    await showTerm(element, undefined);

    expect(search).toHaveBeenCalledTimes(1);
    expect(lastRequest()).toEqual({
      configName: "Support_Portal_Search",
      searchTerm: "",
      selectedFacets: [],
      limitPerObject: null,
      language: "es-MX"
    });
    expect(facetPanel(element).facets).toHaveLength(2);
    expect(statusText(element)).toBe("c.Search_Results_Prompt_Facets");
  });

  it("hides the panel when showFacets is off, even if the server returns facets", async () => {
    search.mockResolvedValue({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets(false);
    await showTerm(element, "password");

    expect(facetPanel(element)).toBeNull();
  });

  it("hides the panel when the config has no facet values", async () => {
    search.mockResolvedValue({
      ...NO_TERM,
      facets: [{ ...FACETS[0], values: [] }]
    });
    const element = createWithFacets();
    await showTerm(element, undefined);

    expect(facetPanel(element)).toBeNull();
    expect(statusText(element)).toBe("c.Search_Results_Prompt");
  });

  it("browses by facet when there is no term", async () => {
    search.mockResolvedValueOnce(NO_TERM).mockResolvedValueOnce(BROWSE);
    const element = createWithFacets();
    await showTerm(element, undefined);
    await changeFacet(element, "Category__c", ["Getting Started"]);

    expect(lastRequest().searchTerm).toBe("");
    expect(lastRequest().selectedFacets).toEqual([
      {
        objectApiName: "Help_Article__c",
        fieldApiName: "Category__c",
        values: ["Getting Started"]
      }
    ]);
    expect(statusText(element)).toBe("3 results");
    expect(
      element.shadowRoot.querySelectorAll("c-search-result-card")
    ).toHaveLength(3);
  });

  it("uses the singular browse message for one result", async () => {
    search
      .mockResolvedValueOnce(NO_TERM)
      .mockResolvedValueOnce({ ...BROWSE, groups: [articleGroup(1, false)] });
    const element = createWithFacets();
    await showTerm(element, undefined);
    await changeFacet(element, "Category__c", ["Billing"]);

    expect(statusText(element)).toBe("c.Search_Results_Count_Browse_One");
  });

  it("says no records match when browsing finds nothing", async () => {
    search
      .mockResolvedValueOnce(NO_TERM)
      .mockResolvedValueOnce({ ...BROWSE, groups: [] });
    const element = createWithFacets();
    await showTerm(element, undefined);
    await changeFacet(element, "Category__c", ["Billing"]);

    expect(statusText(element)).toBe("c.Search_Results_None_Browse");
  });

  it("narrows a term search with the selected facets", async () => {
    search.mockResolvedValue({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets();
    await showTerm(element, "password");
    await changeFacet(element, "Featured__c", ["true"]);

    expect(search).toHaveBeenCalledTimes(2);
    expect(lastRequest().searchTerm).toBe("password");
    expect(lastRequest().selectedFacets).toEqual([
      {
        objectApiName: "Help_Article__c",
        fieldApiName: "Featured__c",
        values: ["true"]
      }
    ]);
  });

  it("combines several facets in one request", async () => {
    search.mockResolvedValue({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets();
    await showTerm(element, "password");
    await changeFacet(element, "Category__c", ["Billing", "Getting Started"]);
    await changeFacet(element, "Featured__c", ["true"]);

    expect(lastRequest().selectedFacets.map((s) => s.fieldApiName)).toEqual([
      "Category__c",
      "Featured__c"
    ]);
    expect(lastRequest().selectedFacets[0].values).toEqual([
      "Billing",
      "Getting Started"
    ]);
  });

  it("says no results with filters when a filtered term search finds nothing", async () => {
    search
      .mockResolvedValueOnce({ ...RESPONSE, facets: FACETS })
      .mockResolvedValueOnce({
        searchTerm: "password",
        mode: "search",
        groups: [],
        facets: FACETS
      });
    const element = createWithFacets();
    await showTerm(element, "password");
    await changeFacet(element, "Category__c", ["Billing"]);

    expect(statusText(element)).toBe(
      'No results for "password" with the selected filters.'
    );
  });

  it("passes the current selection to the panel", async () => {
    search.mockResolvedValue({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets();
    await showTerm(element, "password");
    await changeFacet(element, "Category__c", ["Billing"]);

    const [category, featured] = facetPanel(element).facets;
    expect(category.values.map((v) => v.selected)).toEqual([false, true]);
    expect(featured.values.every((v) => !v.selected)).toBe(true);
  });

  it("drops a facet from the request when its last value is unchecked", async () => {
    search.mockResolvedValue({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets();
    await showTerm(element, "password");
    await changeFacet(element, "Category__c", ["Billing"]);
    await changeFacet(element, "Category__c", []);

    expect(lastRequest().selectedFacets).toEqual([]);
  });

  it("returns to the prompt without calling Apex when filters are cleared and there is no term", async () => {
    search.mockResolvedValueOnce(NO_TERM).mockResolvedValueOnce(BROWSE);
    const element = createWithFacets();
    await showTerm(element, undefined);
    await changeFacet(element, "Category__c", ["Billing"]);

    facetPanel(element).dispatchEvent(new CustomEvent("facetclear"));
    await flushPromises();

    expect(search).toHaveBeenCalledTimes(2);
    expect(statusText(element)).toBe("c.Search_Results_Prompt_Facets");
    expect(element.shadowRoot.querySelector("c-search-result-card")).toBeNull();
    expect(facetPanel(element)).not.toBeNull();
  });

  it("searches again without filters when they are cleared with a term", async () => {
    search.mockResolvedValue({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets();
    await showTerm(element, "password");
    await changeFacet(element, "Category__c", ["Billing"]);

    facetPanel(element).dispatchEvent(new CustomEvent("facetclear"));
    await flushPromises();

    expect(search).toHaveBeenCalledTimes(3);
    expect(lastRequest().selectedFacets).toEqual([]);
  });

  it("keeps the facet panel on screen while a facet change loads", async () => {
    let resolveSecond;
    search.mockResolvedValueOnce({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets();
    await showTerm(element, "password");

    search.mockReturnValueOnce(
      new Promise((resolve) => {
        resolveSecond = resolve;
      })
    );
    await changeFacet(element, "Category__c", ["Billing"]);

    expect(facetPanel(element)).not.toBeNull();
    expect(
      element.shadowRoot.querySelector("lightning-spinner")
    ).not.toBeNull();
    expect(statusText(element)).toBe("c.Search_Results_Loading");

    resolveSecond({ ...RESPONSE, facets: FACETS });
    await flushPromises();
    expect(element.shadowRoot.querySelector("lightning-spinner")).toBeNull();
  });

  it("keeps the facet panel after an error so the visitor can change filters", async () => {
    search
      .mockResolvedValueOnce({ ...RESPONSE, facets: FACETS })
      .mockRejectedValueOnce({ body: { message: "Something went wrong." } });
    const element = createWithFacets();
    await showTerm(element, "password");
    await changeFacet(element, "Category__c", ["Billing"]);

    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent.trim()
    ).toBe("Something went wrong.");
    expect(facetPanel(element)).not.toBeNull();
  });

  it("clears filters when the term in the URL changes", async () => {
    search.mockResolvedValue({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets();
    await showTerm(element, "password");
    await changeFacet(element, "Category__c", ["Billing"]);
    await showTerm(element, "invoice");

    expect(lastRequest().searchTerm).toBe("invoice");
    expect(lastRequest().selectedFacets).toEqual([]);
  });

  it("shows only the result for the newest facet change", async () => {
    let resolveFirst;
    search.mockResolvedValueOnce(NO_TERM);
    const element = createWithFacets();
    await showTerm(element, undefined);

    search
      .mockReturnValueOnce(
        new Promise((resolve) => {
          resolveFirst = resolve;
        })
      )
      .mockResolvedValueOnce({ ...BROWSE, groups: [] });
    await changeFacet(element, "Category__c", ["Billing"]);
    await changeFacet(element, "Category__c", ["Billing", "Getting Started"]);

    resolveFirst(BROWSE);
    await flushPromises();

    expect(statusText(element)).toBe("c.Search_Results_None_Browse");
  });

  it("is accessible with the facet panel and results", async () => {
    search.mockResolvedValue({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets();
    await showTerm(element, "password");
    await changeFacet(element, "Category__c", ["Billing"]);
    await expect(element).toBeAccessible();
  });
});

describe("c-search-results load more", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  const page = (count, hasMore) => ({
    searchTerm: "password",
    mode: "search",
    groups: [articleGroup(count, hasMore), RESPONSE.groups[1]],
    facets: []
  });

  it("shows a 'Load more' button only for groups with more results", async () => {
    search.mockResolvedValue(page(10, true));
    const element = createResults();
    await showTerm(element, "password");

    const buttons = element.shadowRoot.querySelectorAll("lightning-button");
    expect(buttons).toHaveLength(1);
    expect(buttons[0].label).toBe("Load more Help Articles");
  });

  it("asks for one more page per click", async () => {
    search
      .mockResolvedValueOnce(page(10, true))
      .mockResolvedValueOnce(page(20, true))
      .mockResolvedValueOnce(page(30, false));
    const element = createResults();
    await showTerm(element, "password");

    loadMoreButton(element).click();
    await flushPromises();
    expect(lastRequest().limitPerObject).toBe(20);
    expect(lastRequest().searchTerm).toBe("password");

    loadMoreButton(element).click();
    await flushPromises();
    expect(lastRequest().limitPerObject).toBe(30);

    expect(loadMoreButton(element)).toBeNull();
    expect(statusText(element)).toBe('31 results for "password"');
  });

  it("keeps the current results on screen while more load", async () => {
    let resolveMore;
    search.mockResolvedValueOnce(page(10, true)).mockReturnValueOnce(
      new Promise((resolve) => {
        resolveMore = resolve;
      })
    );
    const element = createResults();
    await showTerm(element, "password");

    loadMoreButton(element).click();
    await flushPromises();

    const region = element.shadowRoot.querySelector("section.search-results");
    expect(region.getAttribute("aria-busy")).toBe("true");
    expect(
      element.shadowRoot.querySelectorAll("c-search-result-card")
    ).toHaveLength(11);
    expect(
      element.shadowRoot.querySelector(".search-results__more-spinner")
    ).not.toBeNull();
    expect(statusText(element)).toBe('11 results for "password"');

    resolveMore(page(20, false));
    await flushPromises();
    expect(region.getAttribute("aria-busy")).toBe("false");
    expect(
      element.shadowRoot.querySelector(".search-results__more-spinner")
    ).toBeNull();
    expect(
      element.shadowRoot.querySelectorAll("c-search-result-card")
    ).toHaveLength(21);
  });

  it("ignores a second click while more results load", async () => {
    search
      .mockResolvedValueOnce(page(10, true))
      .mockReturnValueOnce(new Promise(() => {}));
    const element = createResults();
    await showTerm(element, "password");

    loadMoreButton(element).click();
    await flushPromises();
    loadMoreButton(element).click();
    await flushPromises();

    expect(search).toHaveBeenCalledTimes(2);
  });

  it("moves focus to the first new result", async () => {
    search
      .mockResolvedValueOnce(page(10, true))
      .mockResolvedValueOnce(page(20, false));
    const element = createResults();
    await showTerm(element, "password");

    loadMoreButton(element).click();
    await flushPromises();
    await flushPromises();

    const cards = element.shadowRoot.querySelectorAll(
      '[data-group="Help_Article__c"] c-search-result-card'
    );
    const link = cards[10].shadowRoot.querySelector("a");
    expect(cards[10].shadowRoot.activeElement).toBe(link);
  });

  it("keeps the results and shows an error when loading more fails", async () => {
    search
      .mockResolvedValueOnce(page(10, true))
      .mockRejectedValueOnce({ body: { message: "Something went wrong." } });
    const element = createResults();
    await showTerm(element, "password");

    loadMoreButton(element).click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent.trim()
    ).toBe("Something went wrong.");
    expect(
      element.shadowRoot.querySelectorAll("c-search-result-card")
    ).toHaveLength(11);
    expect(loadMoreButton(element)).not.toBeNull();
  });

  it("uses the generic message when loading more fails without one", async () => {
    search
      .mockResolvedValueOnce(page(10, true))
      .mockRejectedValueOnce(new Error("network"));
    const element = createResults();
    await showTerm(element, "password");

    loadMoreButton(element).click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent.trim()
    ).toBe("c.Search_Error_Generic");
  });

  it(`stops offering more at the server cap of ${MAX_LIMIT_PER_OBJECT}`, async () => {
    search
      .mockResolvedValueOnce(page(150, true))
      .mockResolvedValueOnce(page(MAX_LIMIT_PER_OBJECT, true));
    const element = createResults();
    await showTerm(element, "password");

    loadMoreButton(element).click();
    await flushPromises();

    expect(lastRequest().limitPerObject).toBe(MAX_LIMIT_PER_OBJECT);
    expect(loadMoreButton(element)).toBeNull();
  });

  it("starts from the default page size again after a facet change", async () => {
    search
      .mockResolvedValueOnce({ ...page(10, true), facets: FACETS })
      .mockResolvedValueOnce({ ...page(20, true), facets: FACETS })
      .mockResolvedValueOnce({ ...page(10, true), facets: FACETS });
    const element = createWithFacets();
    await showTerm(element, "password");

    loadMoreButton(element).click();
    await flushPromises();
    await changeFacet(element, "Category__c", ["Billing"]);

    expect(lastRequest().limitPerObject).toBeNull();
  });

  it("drops a pending 'Load more' when a facet changes", async () => {
    let resolveMore;
    search
      .mockResolvedValueOnce({ ...page(10, true), facets: FACETS })
      .mockReturnValueOnce(
        new Promise((resolve) => {
          resolveMore = resolve;
        })
      )
      .mockResolvedValueOnce({ ...page(4, false), facets: FACETS });
    const element = createWithFacets();
    await showTerm(element, "password");

    loadMoreButton(element).click();
    await flushPromises();
    await changeFacet(element, "Category__c", ["Billing"]);

    resolveMore({ ...page(20, false), facets: FACETS });
    await flushPromises();

    expect(
      element.shadowRoot.querySelectorAll(
        '[data-group="Help_Article__c"] c-search-result-card'
      )
    ).toHaveLength(4);
  });

  it("is accessible with a 'Load more' button", async () => {
    search.mockResolvedValue(page(10, true));
    const element = createResults();
    await showTerm(element, "password");
    await expect(element).toBeAccessible();
  });
});

describe("formatLabel", () => {
  it("replaces numbered placeholders", () => {
    expect(formatLabel('{0} results for "{1}"', 5, "sync")).toBe(
      '5 results for "sync"'
    );
  });

  it("leaves placeholders without an argument untouched", () => {
    expect(formatLabel("{0} and {1}", "a")).toBe("a and {1}");
  });

  it("does not interpret replacement patterns in arguments", () => {
    expect(formatLabel("term: {0}", "$&$1")).toBe("term: $&$1");
  });
});

describe("c-search-results facets in the URL", () => {
  beforeEach(() => {
    resetNavigationMock();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  const SEARCH_PAGE = {
    type: "comm__namedPage",
    attributes: { name: "Search__c" }
  };

  async function showUrl(element, state) {
    CurrentPageReference.emit({ ...SEARCH_PAGE, state });
    await flushPromises();
  }

  const lastNavigation = () => getNavigateCalls().at(-1);

  it("applies selections from the URL on load", async () => {
    search.mockResolvedValue(BROWSE);
    const element = createWithFacets();
    await showUrl(element, { f: "Help_Article__c.Category__c:Billing" });

    expect(search).toHaveBeenCalledTimes(1);
    expect(lastRequest().selectedFacets).toEqual([
      {
        objectApiName: "Help_Article__c",
        fieldApiName: "Category__c",
        values: ["Billing"]
      }
    ]);
    const [category] = facetPanel(element).facets;
    expect(category.values.map((v) => v.selected)).toEqual([false, true]);
    expect(statusText(element)).toBe("3 results");
  });

  it("combines the term and the selections from the URL", async () => {
    search.mockResolvedValue({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets();
    await showUrl(element, {
      term: "password",
      f: "Help_Article__c.Category__c:Billing,Getting Started;Help_Article__c.Featured__c:true"
    });

    expect(lastRequest().searchTerm).toBe("password");
    expect(lastRequest().selectedFacets.map((s) => s.values)).toEqual([
      ["Billing", "Getting Started"],
      ["true"]
    ]);
  });

  it("ignores selections in the URL when the facet panel is off", async () => {
    search.mockResolvedValue(RESPONSE);
    const element = createWithFacets(false);
    await showUrl(element, {
      term: "password",
      f: "Help_Article__c.Category__c:Billing"
    });

    expect(lastRequest().selectedFacets).toEqual([]);
  });

  it("writes a facet change to the URL as a new history entry", async () => {
    search.mockResolvedValue({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets();
    await showUrl(element, { term: "password", other: "kept" });
    await changeFacet(element, "Category__c", ["Billing", "Getting Started"]);

    const { pageReference, replace } = lastNavigation();
    expect(pageReference).toEqual({
      ...SEARCH_PAGE,
      state: {
        term: "password",
        other: "kept",
        f: "Help_Article__c.Category__c:Billing,Getting Started"
      }
    });
    expect(replace).toBe(false); // a new history entry
  });

  it("removes the parameter when the filters are cleared", async () => {
    search.mockResolvedValue({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets();
    await showUrl(element, {
      term: "password",
      f: "Help_Article__c.Category__c:Billing"
    });

    facetPanel(element).dispatchEvent(new CustomEvent("facetclear"));
    await flushPromises();

    expect(lastNavigation().pageReference.state).toEqual({ term: "password" });
  });

  it("does not search again when the router reports the URL it just wrote", async () => {
    search.mockResolvedValue({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets();
    await showUrl(element, { term: "password" });
    await changeFacet(element, "Category__c", ["Billing"]);
    expect(search).toHaveBeenCalledTimes(2);

    await showUrl(element, lastNavigation().pageReference.state);

    expect(search).toHaveBeenCalledTimes(2);
  });

  it("restores the earlier selections on back", async () => {
    search.mockResolvedValue({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets();
    await showUrl(element, { term: "password" });
    await changeFacet(element, "Category__c", ["Billing"]);
    await showUrl(element, lastNavigation().pageReference.state);
    await changeFacet(element, "Featured__c", ["true"]);
    await showUrl(element, lastNavigation().pageReference.state);

    // Back: the router reports the previous history entry.
    await showUrl(element, {
      term: "password",
      f: "Help_Article__c.Category__c:Billing"
    });

    expect(search).toHaveBeenCalledTimes(4);
    expect(lastRequest().selectedFacets).toEqual([
      {
        objectApiName: "Help_Article__c",
        fieldApiName: "Category__c",
        values: ["Billing"]
      }
    ]);
    const [category, featured] = facetPanel(element).facets;
    expect(category.values.map((v) => v.selected)).toEqual([false, true]);
    expect(featured.values.every((v) => !v.selected)).toBe(true);
  });

  it("drops edited values that the server doesn't offer", async () => {
    search.mockResolvedValue({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets();
    await showUrl(element, {
      term: "password",
      f: "Help_Article__c.Category__c:Billing,Hacked' OR Name != '';Help_Article__c.Secret__c:x;Case.Status:Closed"
    });

    // The first request sends what was parsed; the server validates it.
    expect(lastRequest().selectedFacets).toHaveLength(3);

    await changeFacet(element, "Featured__c", ["true"]);
    expect(lastRequest().selectedFacets).toEqual([
      {
        objectApiName: "Help_Article__c",
        fieldApiName: "Category__c",
        values: ["Billing"]
      },
      {
        objectApiName: "Help_Article__c",
        fieldApiName: "Featured__c",
        values: ["true"]
      }
    ]);
  });

  it("says there are no filters when every value in the URL was invalid", async () => {
    search.mockResolvedValue({
      searchTerm: "password",
      mode: "search",
      groups: [],
      facets: FACETS
    });
    const element = createWithFacets();
    await showUrl(element, {
      term: "password",
      f: "Help_Article__c.Category__c:Nope"
    });

    expect(statusText(element)).toBe('No results for "password".');
  });

  it("clears the selections when searchBox navigates with a new term", async () => {
    search.mockResolvedValue({ ...RESPONSE, facets: FACETS });
    const element = createWithFacets();
    await showUrl(element, {
      term: "password",
      f: "Help_Article__c.Category__c:Billing"
    });
    await showUrl(element, { term: "invoice" });

    expect(lastRequest().searchTerm).toBe("invoice");
    expect(lastRequest().selectedFacets).toEqual([]);
  });
});

describe("serializeSelections and parseSelections", () => {
  const selection = (objectApiName, fieldApiName, values) => [
    facetKey(objectApiName, fieldApiName),
    { objectApiName, fieldApiName, values }
  ];

  it("writes nothing when nothing is selected", () => {
    expect(serializeSelections(new Map())).toBe("");
    expect(
      serializeSelections(new Map([selection("Case", "Status", [])]))
    ).toBe("");
  });

  it("round-trips values that contain separators", () => {
    const selections = new Map([
      selection("Help_Article__c", "Category__c", [
        "Billing, Accounts",
        "50% off; today",
        "a:b"
      ]),
      selection("Case", "IsEscalated", ["true"])
    ]);

    const serialized = serializeSelections(selections);

    expect(serialized).toBe(
      "Help_Article__c.Category__c:Billing%2C Accounts,50%25 off%3B today,a:b;Case.IsEscalated:true"
    );
    expect(parseSelections(serialized)).toEqual(selections);
  });

  it("skips malformed parts and keeps the valid ones", () => {
    const parsed = parseSelections(
      [
        "Case.Status:New",
        "no-colon",
        ":Value",
        "Bad Key.Field:x",
        "Case.Status__c.Extra:x",
        "<script>.x:y",
        "Case.Priority:%E0%A4%A,High",
        "Case.Origin:",
        "Case.Status:New,Working"
      ].join(";")
    );

    expect([...parsed.values()]).toEqual([
      {
        objectApiName: "Case",
        fieldApiName: "Status",
        values: ["New", "Working"]
      },
      { objectApiName: "Case", fieldApiName: "Priority", values: ["High"] }
    ]);
  });

  it("ignores missing, non-string and oversized input", () => {
    expect(parseSelections(undefined).size).toBe(0);
    expect(parseSelections(["Case.Status:New"]).size).toBe(0);
    expect(parseSelections(`Case.Status:${"x".repeat(2001)}`).size).toBe(0);
  });

  it("caps the number of facets and values read", () => {
    const manyFacets = Array.from(
      { length: 60 },
      (_, i) => `Case.Field${i}__c:x`
    ).join(";");
    const manyValues = `Case.Status:${Array.from({ length: 150 }, (_, i) => `v${i}`).join(",")}`;

    expect(parseSelections(manyFacets).size).toBe(50);
    expect(parseSelections(manyValues).get("Case.Status").values).toHaveLength(
      100
    );
  });
});

describe("appendResults", () => {
  const result = (id) => ({ recordId: id, title: id, details: [] });
  const group = (objectApiName, ids, hasMore = false) => ({
    objectApiName,
    sectionLabel: objectApiName,
    totalShown: ids.length,
    hasMore,
    results: ids.map(result)
  });

  it("keeps the shown results in place and appends new ones", () => {
    const previous = { groups: [group("A", ["a1", "a2", "a3"], true)] };
    // The larger pool ranked a new boosted record (n1) first and pushed a3 out.
    const next = {
      mode: "search",
      groups: [group("A", ["n1", "a1", "a2", "n2", "n3", "n4"], false)]
    };

    const merged = appendResults(previous, next);

    expect(merged.groups[0].results.map((r) => r.recordId)).toEqual([
      "a1",
      "a2",
      "a3",
      "n1",
      "n2",
      "n3"
    ]);
    expect(merged.groups[0].totalShown).toBe(6);
    expect(merged.groups[0].hasMore).toBe(false);
    expect(merged.mode).toBe("search");
  });

  it("takes groups that weren't shown before as they are", () => {
    const previous = { groups: [group("A", ["a1"])] };
    const next = { groups: [group("A", ["a1", "a2"]), group("B", ["b1"])] };

    const merged = appendResults(previous, next);

    expect(merged.groups.map((g) => g.objectApiName)).toEqual(["A", "B"]);
    expect(merged.groups[1]).toBe(next.groups[1]);
  });

  it("returns the new response when there is nothing to merge", () => {
    const next = { groups: [group("A", ["a1"])] };
    expect(appendResults(undefined, next)).toBe(next);
    expect(appendResults({ groups: [] }, undefined)).toBeUndefined();
  });
});

describe("c-search-results load more keeps results in place", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("appends a newly fetched boosted record after the results already shown", async () => {
    const first = articleGroup(10, true);
    const boosted = {
      recordId: "a0000000000BOOSTAAA",
      title: "Featured article",
      score: 99,
      details: []
    };
    const second = {
      ...articleGroup(20, false),
      results: [boosted, ...articleGroup(19, false).results]
    };
    search
      .mockResolvedValueOnce({
        searchTerm: "password",
        mode: "search",
        groups: [first],
        facets: []
      })
      .mockResolvedValueOnce({
        searchTerm: "password",
        mode: "search",
        groups: [second],
        facets: []
      });
    const element = createResults();
    await showTerm(element, "password");

    loadMoreButton(element).click();
    await flushPromises();

    const titles = [
      ...element.shadowRoot.querySelectorAll("c-search-result-card")
    ].map((card) => card.result.title);
    expect(titles.slice(0, 10)).toEqual(first.results.map((r) => r.title));
    expect(titles[10]).toBe("Featured article");
    expect(titles).toHaveLength(20);
    expect(statusText(element)).toBe('20 results for "password"');
  });
});

// ---- object tabs (M8.5) ----

jest.mock(
  "@salesforce/label/c.Search_Results_View_All",
  () => ({ default: "View all {0}" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/label/c.Search_Results_Heading",
  () => ({ default: "Results for “{0}”" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/label/c.Search_Results_Heading_Browse",
  () => ({ default: "Results" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/label/c.Search_Results_Tab_All",
  () => ({ default: "All" }),
  { virtual: true }
);

describe("parseObjectParam", () => {
  it("accepts API names only", () => {
    expect(parseObjectParam("Case")).toBe("Case");
    expect(parseObjectParam("Help_Article__c")).toBe("Help_Article__c");
    for (const bad of [
      undefined,
      null,
      "",
      42,
      ["Case"],
      "Case,Account",
      "Case)",
      "1Case",
      "Case Account",
      "<script>",
      "A".repeat(81)
    ]) {
      expect(parseObjectParam(bad)).toBe("");
    }
  });
});

describe("c-search-results object tabs", () => {
  beforeEach(() => {
    resetNavigationMock();
    // Drops one-time responses another test left queued.
    search.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  const SEARCH_PAGE = {
    type: "comm__namedPage",
    attributes: { name: "Search__c" }
  };

  const OBJECTS = [
    {
      objectApiName: "Help_Article__c",
      sectionLabel: "Help Articles",
      iconName: "standard:article"
    },
    { objectApiName: "Case", sectionLabel: "Cases", iconName: "standard:case" }
  ];

  const CASE_FACETS = [
    {
      objectApiName: "Case",
      sectionLabel: "Cases",
      fieldApiName: "Status",
      label: "Status",
      values: [
        { value: "New", label: "New", selected: false },
        { value: "Closed", label: "Closed", selected: false }
      ]
    }
  ];

  /** All tab: articles have more results, cases don't. */
  const ALL = {
    ...RESPONSE,
    objects: OBJECTS,
    facets: [...FACETS, ...CASE_FACETS],
    groups: [articleGroup(2, true), RESPONSE.groups[1]]
  };

  /** Cases tab: only the Case group and its facets. */
  const CASES = {
    ...RESPONSE,
    objects: OBJECTS,
    facets: CASE_FACETS,
    groups: [{ ...RESPONSE.groups[1], hasMore: true }]
  };

  function createWithTabs(showObjectTabs = true) {
    const element = createElement("c-search-results", { is: SearchResults });
    element.configName = "Support_Portal_Search";
    element.showFacets = true;
    element.showObjectTabs = showObjectTabs;
    document.body.appendChild(element);
    return element;
  }

  async function showUrl(element, state) {
    CurrentPageReference.emit({ ...SEARCH_PAGE, state });
    await flushPromises();
  }

  const tabs = (element) => [
    ...element.shadowRoot.querySelectorAll('[role="tab"]')
  ];
  const selectedTab = (element) =>
    tabs(element).find((tab) => tab.getAttribute("aria-selected") === "true");
  const tabByObject = (element, objectApiName) =>
    tabs(element).find((tab) => tab.dataset.objectApiName === objectApiName);
  const lastNavigation = () => getNavigateCalls().at(-1);

  async function clickTab(element, objectApiName) {
    tabByObject(element, objectApiName).click();
    await flushPromises();
  }

  describe("filter panel across tabs", () => {
    const WITH_KNOWLEDGE = [
      { ...OBJECTS[0], hasFacets: true },
      { ...OBJECTS[1], hasFacets: true },
      {
        objectApiName: "Knowledge__kav",
        sectionLabel: "Knowledge Base",
        iconName: "standard:knowledge",
        hasFacets: false
      }
    ];
    const ALL_K = { ...ALL, objects: WITH_KNOWLEDGE };
    const KNOWLEDGE_TAB = {
      ...RESPONSE,
      objects: WITH_KNOWLEDGE,
      facets: [],
      groups: []
    };
    const layout = (element) =>
      element.shadowRoot.querySelector(".search-results__layout");

    it("stays in place on a tab whose object has no filters", async () => {
      search.mockResolvedValueOnce(ALL_K).mockResolvedValueOnce(KNOWLEDGE_TAB);
      const element = createWithTabs();
      await showUrl(element, { term: "password" });
      await clickTab(element, "Knowledge__kav");

      expect(facetPanel(element)).not.toBeNull();
      expect(facetPanel(element).facets).toEqual([]);
      expect(layout(element).classList).toContain(
        "search-results__layout_with-facets"
      );
    });

    it("starts collapsed and stays open across tabs once opened", async () => {
      search
        .mockResolvedValueOnce(ALL_K)
        .mockResolvedValueOnce({ ...CASES, objects: WITH_KNOWLEDGE });
      const element = createWithTabs();
      await showUrl(element, { term: "password" });
      expect(facetPanel(element).expanded).toBe(false);

      facetPanel(element).dispatchEvent(
        new CustomEvent("facettoggle", { detail: { expanded: true } })
      );
      await flushPromises();
      expect(facetPanel(element).expanded).toBe(true);
      expect(layout(element).classList).toContain(
        "search-results__layout_facets-open"
      );

      await clickTab(element, "Case");
      expect(facetPanel(element).expanded).toBe(true);
    });

    it("isn't shown when no object of the config has filters", async () => {
      const objects = WITH_KNOWLEDGE.map((object) => ({
        ...object,
        hasFacets: false
      }));
      search.mockResolvedValue({ ...ALL, objects, facets: [] });
      const element = createWithTabs();
      await showUrl(element, { term: "password" });

      expect(facetPanel(element)).toBeNull();
    });
  });

  it("shows an All tab plus one tab per object, with All selected", async () => {
    search.mockResolvedValue(ALL);
    const element = createWithTabs();
    await showUrl(element, { term: "password" });

    expect(tabs(element).map((tab) => tab.textContent.trim())).toEqual([
      "All",
      "Help Articles",
      "Cases"
    ]);
    expect(selectedTab(element).textContent.trim()).toBe("All");
    expect(lastRequest().objectApiNames).toBeUndefined();
    const tablist = element.shadowRoot.querySelector('[role="tablist"]');
    expect(tablist.getAttribute("aria-label")).toBeTruthy();
    const panel = element.shadowRoot.querySelector('[role="tabpanel"]');
    expect(panel.getAttribute("aria-labelledby")).toBe(selectedTab(element).id);
  });

  it("shows a heading with the searched term", async () => {
    search.mockResolvedValue(ALL);
    const element = createWithTabs();
    await showUrl(element, { term: "password" });

    expect(element.shadowRoot.querySelector("h2").textContent.trim()).toBe(
      "Results for “password”"
    );
  });

  it("has no tabs when the property is off or there is one object", async () => {
    search.mockResolvedValue(ALL);
    const off = createWithTabs(false);
    await showUrl(off, { term: "password", o: "Case" });
    expect(tabs(off)).toHaveLength(0);
    expect(lastRequest().objectApiNames).toBeUndefined();
    // No tab panel role without tabs.
    expect(off.shadowRoot.querySelector('[role="tabpanel"]')).toBeNull();

    search.mockResolvedValue({ ...ALL, objects: [OBJECTS[0]] });
    const single = createWithTabs();
    await showUrl(single, { term: "password" });
    expect(tabs(single)).toHaveLength(0);
  });

  it("has no tabs before a search", async () => {
    search.mockResolvedValue({ ...NO_TERM, objects: OBJECTS });
    const element = createWithTabs();
    await showUrl(element, {});

    expect(tabs(element)).toHaveLength(0);
  });

  it("selecting a tab searches only that object and writes it to the URL", async () => {
    search.mockResolvedValueOnce(ALL).mockResolvedValueOnce(CASES);
    const element = createWithTabs();
    await showUrl(element, { term: "password" });
    await clickTab(element, "Case");

    expect(lastRequest().objectApiNames).toEqual(["Case"]);
    expect(lastRequest().limitPerObject).toBeNull();
    expect(selectedTab(element).dataset.objectApiName).toBe("Case");
    expect(lastNavigation().pageReference.state).toEqual({
      term: "password",
      o: "Case"
    });
    const headings = [...element.shadowRoot.querySelectorAll("h3")].map(
      (node) => node.textContent.trim()
    );
    expect(headings).toEqual(["Cases"]);
    expect(facetPanel(element).facets.map((f) => f.fieldApiName)).toEqual([
      "Status"
    ]);
  });

  it("clicking the selected tab does nothing", async () => {
    search.mockResolvedValue(ALL);
    const element = createWithTabs();
    await showUrl(element, { term: "password" });
    await clickTab(element, "");

    expect(search).toHaveBeenCalledTimes(1);
  });

  it("restores the tab from the URL, and back to All removes it", async () => {
    search.mockResolvedValue(CASES);
    const element = createWithTabs();
    await showUrl(element, { term: "password", o: "Case" });

    expect(search).toHaveBeenCalledTimes(1);
    expect(lastRequest().objectApiNames).toEqual(["Case"]);
    expect(selectedTab(element).dataset.objectApiName).toBe("Case");

    search.mockResolvedValue(ALL);
    await showUrl(element, { term: "password" }); // back button
    expect(search).toHaveBeenCalledTimes(2);
    expect(lastRequest().objectApiNames).toBeUndefined();
    expect(selectedTab(element).dataset.objectApiName).toBe("");
  });

  it("does not search again when the router echoes the tab it wrote", async () => {
    search.mockResolvedValueOnce(ALL).mockResolvedValueOnce(CASES);
    const element = createWithTabs();
    await showUrl(element, { term: "password" });
    await clickTab(element, "Case");
    await showUrl(element, lastNavigation().pageReference.state);

    expect(search).toHaveBeenCalledTimes(2);
  });

  it("ignores a malformed o= and falls back to All for an unknown object", async () => {
    search.mockResolvedValue(ALL);
    const element = createWithTabs();
    await showUrl(element, { term: "password", o: "Case) OR (1" });
    expect(lastRequest().objectApiNames).toBeUndefined();

    await showUrl(element, { term: "password", o: "User" });
    expect(lastRequest().objectApiNames).toEqual(["User"]);
    // The server didn't list User, so the component shows All and fixes the URL in place.
    expect(selectedTab(element).dataset.objectApiName).toBe("");
    expect(tabs(element)).toHaveLength(3);
    const { pageReference, replace } = lastNavigation();
    expect(replace).toBe(true);
    expect(pageReference.state).toEqual({ term: "password" });

    // The router reports the corrected URL: no new search, tabs stay.
    const calls = search.mock.calls.length;
    await showUrl(element, pageReference.state);
    expect(search.mock.calls.length).toBe(calls);
    expect(tabs(element)).toHaveLength(3);
  });

  it("loads an unknown o= on a fresh page with tabs, and a reload of the fixed URL too", async () => {
    search.mockResolvedValue(ALL);
    const element = createWithTabs();
    await showUrl(element, { term: "password", o: "Foo" });

    expect(tabs(element)).toHaveLength(3);
    expect(lastNavigation().pageReference.state).toEqual({ term: "password" });

    document.body.removeChild(element);
    const reloaded = createWithTabs();
    await showUrl(reloaded, lastNavigation().pageReference.state);
    expect(tabs(reloaded)).toHaveLength(3);
    expect(selectedTab(reloaded).dataset.objectApiName).toBe("");
  });

  it("matches o= ignoring case, like the server, and fixes the URL", async () => {
    search.mockResolvedValue(CASES);
    const element = createWithTabs();
    await showUrl(element, { term: "password", o: "case" });

    expect(selectedTab(element).dataset.objectApiName).toBe("Case");
    const { pageReference, replace } = lastNavigation();
    expect(replace).toBe(true);
    expect(pageReference.state).toEqual({ term: "password", o: "Case" });
  });

  it("leaves the URL alone when the tab from it is valid", async () => {
    search.mockResolvedValue(CASES);
    const element = createWithTabs();
    await showUrl(element, { term: "password", o: "Case" });

    expect(getNavigateCalls()).toHaveLength(0);
  });

  it("a new term from the search box goes back to All", async () => {
    search.mockResolvedValue(CASES);
    const element = createWithTabs();
    await showUrl(element, { term: "password", o: "Case" });
    search.mockResolvedValue(ALL);
    await showUrl(element, { term: "invoice" });

    expect(lastRequest().objectApiNames).toBeUndefined();
    expect(selectedTab(element).dataset.objectApiName).toBe("");
  });

  it("offers View all instead of Load more on the All tab", async () => {
    search.mockResolvedValueOnce(ALL).mockResolvedValueOnce(CASES);
    const element = createWithTabs();
    await showUrl(element, { term: "password" });

    expect(loadMoreButton(element)).toBeNull();
    const viewAll = element.shadowRoot.querySelector(
      'button[data-object-api-name="Help_Article__c"]:not([role="tab"])'
    );
    expect(viewAll.textContent.trim()).toBe("View all Help Articles");
    // No View all for a group without more results.
    expect(
      element.shadowRoot.querySelector(
        'button[data-object-api-name="Case"]:not([role="tab"])'
      )
    ).toBeNull();

    viewAll.click();
    await flushPromises();

    expect(lastRequest().objectApiNames).toEqual(["Help_Article__c"]);
    expect(element.shadowRoot.activeElement).toBe(
      tabByObject(element, "Help_Article__c")
    );
  });

  it("Load more on an object tab grows only that object", async () => {
    search.mockResolvedValueOnce(CASES).mockResolvedValueOnce({
      ...CASES,
      groups: [
        {
          ...CASES.groups[0],
          hasMore: false,
          results: [
            ...CASES.groups[0].results,
            {
              recordId: "500000000000002AAA",
              title: "Second case",
              score: 0,
              details: []
            }
          ]
        }
      ]
    });
    const element = createWithTabs();
    await showUrl(element, { term: "password", o: "Case" });
    element.shadowRoot
      .querySelector('lightning-button[data-object-api-name="Case"]')
      .click();
    await flushPromises();

    expect(lastRequest().objectApiNames).toEqual(["Case"]);
    expect(lastRequest().limitPerObject).toBe(2);
    expect(
      element.shadowRoot.querySelectorAll("c-search-result-card")
    ).toHaveLength(2);
  });

  it("keeps other objects' selections in the URL but sends only this tab's", async () => {
    search.mockResolvedValueOnce(ALL).mockResolvedValue(CASES);
    const element = createWithTabs();
    await showUrl(element, {
      term: "password",
      f: "Help_Article__c.Category__c:Billing;Case.Status:Closed"
    });
    await clickTab(element, "Case");

    expect(lastRequest().selectedFacets).toEqual([
      { objectApiName: "Case", fieldApiName: "Status", values: ["Closed"] }
    ]);
    expect(lastNavigation().pageReference.state.f).toBe(
      "Help_Article__c.Category__c:Billing;Case.Status:Closed"
    );

    // Clear on the Cases tab clears only the Status filter.
    facetPanel(element).dispatchEvent(new CustomEvent("facetclear"));
    await flushPromises();
    expect(lastNavigation().pageReference.state).toEqual({
      term: "password",
      o: "Case",
      f: "Help_Article__c.Category__c:Billing"
    });
  });

  it("moves focus between tabs with arrow keys, Home and End", async () => {
    search.mockResolvedValue(ALL);
    const element = createWithTabs();
    await showUrl(element, { term: "password" });
    const [all, articles, cases] = tabs(element);

    expect(all.tabIndex).toBe(0);
    expect(articles.tabIndex).toBe(-1);

    const press = (tab, key) =>
      tab.dispatchEvent(
        new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true })
      );
    all.focus();
    press(all, "ArrowRight");
    expect(element.shadowRoot.activeElement).toBe(articles);
    press(articles, "End");
    expect(element.shadowRoot.activeElement).toBe(cases);
    press(cases, "ArrowRight");
    expect(element.shadowRoot.activeElement).toBe(all);
    press(all, "ArrowLeft");
    expect(element.shadowRoot.activeElement).toBe(cases);
    press(cases, "Home");
    expect(element.shadowRoot.activeElement).toBe(all);
    press(all, "a");
    expect(element.shadowRoot.activeElement).toBe(all);

    // Moving focus does not search.
    expect(search).toHaveBeenCalledTimes(1);
  });

  it("is accessible with tabs", async () => {
    search.mockResolvedValue(ALL);
    const element = createWithTabs();
    await showUrl(element, { term: "password" });

    await expect(element).toBeAccessible();
  });

  it("is accessible on an object tab", async () => {
    search.mockResolvedValue(CASES);
    const element = createWithTabs();
    await showUrl(element, { term: "password", o: "Case" });

    await expect(element).toBeAccessible();
  });
});
