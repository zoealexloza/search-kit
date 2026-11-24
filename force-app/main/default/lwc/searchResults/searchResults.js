import { LightningElement, api, wire } from "lwc";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import search from "@salesforce/apex/SiteSearchController.search";
// The visitor's current site language. Apex sees a guest user's own language instead, so it is
// sent with each request (Knowledge articles are searched in it; the server validates it).
import LANGUAGE from "@salesforce/i18n/lang";
import { facetKey } from "c/searchFacets";
import promptLabel from "@salesforce/label/c.Search_Results_Prompt";
import promptFacetsLabel from "@salesforce/label/c.Search_Results_Prompt_Facets";
import tooShortLabel from "@salesforce/label/c.Search_Results_Term_Too_Short";
import loadingLabel from "@salesforce/label/c.Search_Results_Loading";
import noneLabel from "@salesforce/label/c.Search_Results_None";
import noneFilteredLabel from "@salesforce/label/c.Search_Results_None_Filtered";
import noneBrowseLabel from "@salesforce/label/c.Search_Results_None_Browse";
import countOneLabel from "@salesforce/label/c.Search_Results_Count_One";
import countManyLabel from "@salesforce/label/c.Search_Results_Count_Many";
import countBrowseOneLabel from "@salesforce/label/c.Search_Results_Count_Browse_One";
import countBrowseManyLabel from "@salesforce/label/c.Search_Results_Count_Browse_Many";
import loadMoreLabel from "@salesforce/label/c.Search_Results_Load_More";
import configMissingLabel from "@salesforce/label/c.Search_Error_Config_Not_Found";
import genericErrorLabel from "@salesforce/label/c.Search_Error_Generic";
import headingLabel from "@salesforce/label/c.Search_Results_Heading";
import headingBrowseLabel from "@salesforce/label/c.Search_Results_Heading_Browse";
import tabAllLabel from "@salesforce/label/c.Search_Results_Tab_All";
import tabsLabel from "@salesforce/label/c.Search_Results_Tabs";
import viewAllLabel from "@salesforce/label/c.Search_Results_View_All";

/** Query-string key written by searchBox. */
const TERM_PARAM = "term";

/** Query-string key for facet selections (see serializeSelections). */
export const FACETS_PARAM = "f";

/** Query-string key for the object tab (an object API name; absent means All). */
export const OBJECT_PARAM = "o";

/** An object API name: letters, digits and underscores, starting with a letter. */
const API_NAME_PATTERN = /^[A-Za-z][A-Za-z0-9_]{0,79}$/;

/**
 * Reads the object tab from the query string. Untrusted: anything that isn't shaped like an
 * API name is ignored (All), and the server only scopes to objects of the active config.
 * @param {string} raw value of the o parameter
 * @returns {string} the object API name, or "" for All
 */
export function parseObjectParam(raw) {
  return typeof raw === "string" && API_NAME_PATTERN.test(raw) ? raw : "";
}

/** Bounds on what is read from the URL. The server applies its own limits as well. */
const MAX_URL_LENGTH = 2000;
const MAX_URL_FACETS = 50;
const MAX_URL_VALUES = 100;

/** Object.Field, with API-name characters only. */
const FACET_KEY_PATTERN = /^[A-Za-z][A-Za-z0-9_]*\.[A-Za-z][A-Za-z0-9_]*$/;

/** Mirror SearchResponseDto.MODE_*. */
const MODE_NONE = "none";
const MODE_BROWSE = "browse";

/** Mirrors SearchQueryBuilder.MIN_TERM_LENGTH. Only used to pick the right message. */
const MIN_TERM_LENGTH = 2;

/** Mirrors SearchService.MAX_LIMIT_PER_OBJECT: the server never returns more per object. */
export const MAX_LIMIT_PER_OBJECT = 200;

const STATUS = Object.freeze({
  IDLE: "idle",
  LOADING: "loading",
  LOADING_MORE: "loadingMore",
  TOO_SHORT: "tooShort",
  EMPTY: "empty",
  RESULTS: "results",
  ERROR: "error"
});

/** Replaces {0}, {1}, ... in a Custom Label. */
export function formatLabel(label, ...args) {
  return label.replace(/\{(\d+)\}/g, (match, index) => {
    return index < args.length ? String(args[index]) : match;
  });
}

/** Escapes the characters that separate values and facets in the URL. */
const escapeValue = (value) =>
  String(value).replace(/[%,;]/g, (char) => encodeURIComponent(char));

/**
 * Writes facet selections for the query string:
 * `Object.Field:value1,value2;Object.Field:value`. Only %, comma and semicolon inside values
 * are escaped, so URLs stay readable. Returns "" when nothing is selected.
 * @param {Map} selections facetKey -> { objectApiName, fieldApiName, values[] }
 * @returns {string}
 */
export function serializeSelections(selections) {
  return [...selections.values()]
    .filter((selection) => selection.values?.length)
    .map(
      ({ objectApiName, fieldApiName, values }) =>
        `${facetKey(objectApiName, fieldApiName)}:${values.map(escapeValue).join(",")}`
    )
    .join(";");
}

/**
 * Reads facet selections from the query string (the reverse of serializeSelections).
 * The URL is untrusted input: anything malformed is skipped, sizes are capped, and the server
 * still validates every facet and value against the config.
 * @param {string} raw value of the f parameter
 * @returns {Map} facetKey -> { objectApiName, fieldApiName, values[] }
 */
export function parseSelections(raw) {
  const selections = new Map();
  if (typeof raw !== "string" || !raw || raw.length > MAX_URL_LENGTH) {
    return selections;
  }
  for (const part of raw.split(";").slice(0, MAX_URL_FACETS)) {
    const separator = part.indexOf(":");
    const key = part.slice(0, separator);
    if (separator < 1 || !FACET_KEY_PATTERN.test(key)) {
      continue;
    }
    const values = selections.get(key)?.values ?? [];
    const encodedValues = part
      .slice(separator + 1)
      .split(",")
      .slice(0, MAX_URL_VALUES);
    for (const encoded of encodedValues) {
      const value = decodeValue(encoded);
      if (value && !values.includes(value)) {
        values.push(value);
      }
    }
    if (values.length) {
      const [objectApiName, fieldApiName] = key.split(".");
      selections.set(key, { objectApiName, fieldApiName, values });
    }
  }
  return selections;
}

/** Decodes one value; a malformed escape sequence yields null. */
function decodeValue(encoded) {
  try {
    return decodeURIComponent(encoded);
  } catch {
    return null;
  }
}

/**
 * After "Load more": keeps the results already shown in place and appends the new ones.
 * The server ranks a larger pool on every request, so without this a record already read
 * could move down, or a newly fetched boosted record could appear above it.
 * @param {object} previous response on screen
 * @param {object} next response for the larger limit
 * @returns {object} next, with each group's results merged
 */
export function appendResults(previous, next) {
  if (!previous?.groups || !next?.groups) {
    return next;
  }
  const previousGroups = new Map(
    previous.groups.map((group) => [group.objectApiName, group])
  );
  const groups = next.groups.map((group) => {
    const shown = previousGroups.get(group.objectApiName)?.results ?? [];
    const fetched = group.results ?? [];
    if (!shown.length) {
      return group;
    }
    const shownIds = new Set(shown.map((result) => result.recordId));
    const added = fetched
      .filter((result) => !shownIds.has(result.recordId))
      .slice(0, Math.max(fetched.length - shown.length, 0));
    const results = [...shown, ...added];
    return { ...group, results, totalShown: results.length };
  });
  return { ...next, groups };
}

/**
 * Search results page component. Reads the term from the page URL (?term=), runs the search
 * through SiteSearchController and renders results grouped by object, with an optional facet
 * panel (c-search-facets) and a "Load more" button per object.
 *
 * This component owns all search state (term, facet selections, results per object), and
 * searchFacets is a child that only reports changes. One component on the page means one
 * Apex call per change and nothing for the admin to connect between components.
 */
export default class SearchResults extends NavigationMixin(LightningElement) {
  /** DeveloperName of the Search_Config__mdt record (picked in Experience Builder). */
  @api configName;

  /** Shows the facet panel. Experience Builder defaults it to true (js-meta.xml). */
  @api showFacets = false;

  /** Starts each filter in the panel collapsed (Experience Builder property, default off). */
  @api collapseFilters = false;

  /**
   * Shows an "All" tab plus one tab per object, so visitors can search one object.
   * Experience Builder defaults it to true (js-meta.xml).
   */
  @api showObjectTabs = false;

  status = STATUS.IDLE;
  term = "";
  response;
  errorMessage;
  loadMoreError;

  /** Facet definitions from the last successful response, kept while a new search runs. */
  facets = [];

  /** Selected facet values: facetKey -> { objectApiName, fieldApiName, values[] }. */
  selections = new Map();

  /** Results per object to ask for; null means the config's default. */
  limitPerObject = null;

  /** Object API name of the selected tab; "" means All. */
  activeObject = "";

  /** Whether the filter panel is open. Starts closed; kept across tabs and searches. */
  filtersExpanded = false;

  /** Objects the visitor can search (SearchResponseDto.objects), kept while a search runs. */
  objects = [];

  label = { loadingLabel, tabsLabel };

  /** Ignores responses to searches that a newer search has replaced. */
  _requestId = 0;
  _initialized = false;
  _facetsLoaded = false;
  /** The config's page size, learned from the first "Load more". */
  _pageSize;
  /** Object whose "Load more" is running. */
  _loadingMoreFor;
  /** After "Load more": { objectApiName, index } of the first new result, to focus it. */
  _focusAfterLoad;
  /** Latest page reference, used to write facet selections to the URL. */
  _pageReference;
  /** Tab to focus after the next render ("View all" moves focus to the tab it selects). */
  _focusTab;

  /**
   * The URL holds the term and the facet selections. searchBox navigates with a term only, so
   * filters don't carry over to a new search; back and forward restore the selections of that
   * history entry. "Load more" isn't kept in the URL.
   */
  @wire(CurrentPageReference)
  handlePageReference(pageReference) {
    this._pageReference = pageReference;
    const raw = pageReference?.state?.[TERM_PARAM];
    const term = typeof raw === "string" ? raw.trim() : "";
    // Selections from the URL only apply when the visitor can see (and change) them.
    const selections = this.showFacets
      ? parseSelections(pageReference?.state?.[FACETS_PARAM])
      : new Map();
    const activeObject = this.showObjectTabs
      ? parseObjectParam(pageReference?.state?.[OBJECT_PARAM])
      : "";
    if (
      !this._initialized ||
      term !== this.term ||
      activeObject !== this.activeObject ||
      serializeSelections(selections) !== serializeSelections(this.selections)
    ) {
      this._initialized = true;
      this.term = term;
      this.selections = selections;
      this.activeObject = activeObject;
      this.limitPerObject = null;
      this.runSearch();
    }
  }

  /**
   * Whether a selection belongs to the objects being searched. On an object tab, selections
   * for other objects stay in the URL (they apply again on All) but aren't sent or counted.
   */
  inScope(selection) {
    return !this.activeObject || selection.objectApiName === this.activeObject;
  }

  get scopedSelections() {
    return [...this.selections.values()].filter((selection) =>
      this.inScope(selection)
    );
  }

  get hasSelection() {
    return this.scopedSelections.length > 0;
  }

  async runSearch({ more = false } = {}) {
    const requestId = ++this._requestId;
    this.errorMessage = undefined;
    this.loadMoreError = undefined;
    if (!more) {
      this.response = undefined;
      this._focusAfterLoad = undefined;
      this._loadingMoreFor = undefined;
    }

    // Without a term or a selection there is nothing to search. Apex is still called once
    // when the facet panel is shown, because the response carries the facet definitions.
    if (
      !this.term &&
      !this.hasSelection &&
      (!this.showFacets || this._facetsLoaded)
    ) {
      this.status = STATUS.IDLE;
      return;
    }
    if (!this.configName) {
      this.showError(configMissingLabel);
      return;
    }

    this.status = more ? STATUS.LOADING_MORE : STATUS.LOADING;
    try {
      const request = {
        configName: this.configName,
        searchTerm: this.term,
        selectedFacets: this.scopedSelections,
        limitPerObject: this.limitPerObject,
        language: LANGUAGE
      };
      if (this.activeObject) {
        request.objectApiNames = [this.activeObject];
      }
      const response = await search({ request });
      if (requestId !== this._requestId) {
        return;
      }
      this.response = more ? appendResults(this.response, response) : response;
      this.facets = response?.facets ?? [];
      this.objects = response?.objects ?? [];
      const tabCorrected = this.matchActiveObject();
      this.dropUnknownSelections();
      this._facetsLoaded = true;
      this.status = this.statusFor(response);
      if (tabCorrected) {
        // Make the URL say what the page shows, so a reload or a repeated page reference
        // from the router lands on the same tab instead of the edited value.
        this.writeStateToUrl({ replace: true });
      }
    } catch (error) {
      if (requestId !== this._requestId) {
        return;
      }
      const message = error?.body?.message || genericErrorLabel;
      if (more) {
        // Keep the results already on screen; only the extra page failed.
        this.loadMoreError = message;
        this._focusAfterLoad = undefined;
        this.status = STATUS.RESULTS;
      } else {
        this.showError(message);
      }
    } finally {
      if (requestId === this._requestId) {
        this._loadingMoreFor = undefined;
      }
    }
  }

  statusFor(response) {
    if (response?.mode === MODE_NONE) {
      if (!this.term) {
        return STATUS.IDLE;
      }
      if ((response.searchTerm ?? "").length < MIN_TERM_LENGTH) {
        return STATUS.TOO_SHORT;
      }
    }
    // A valid term with nothing searchable (mode none) reads as "no results" to a visitor.
    return response?.groups?.length ? STATUS.RESULTS : STATUS.EMPTY;
  }

  /**
   * Drops selected values that the server doesn't offer (for example from an edited URL), so
   * the panel, the next request and the messages agree. The server has already ignored them.
   */
  dropUnknownSelections() {
    if (!this.hasSelection) {
      return;
    }
    const offered = new Map(
      this.facets.map((facet) => [
        facetKey(facet.objectApiName, facet.fieldApiName),
        new Set((facet.values ?? []).map((value) => value.value))
      ])
    );
    const kept = new Map();
    for (const [key, selection] of this.selections) {
      if (!this.inScope(selection)) {
        kept.set(key, selection);
        continue;
      }
      const values = selection.values.filter((value) =>
        offered.get(key)?.has(value)
      );
      if (values.length) {
        kept.set(key, { ...selection, values });
      }
    }
    if (serializeSelections(kept) !== serializeSelections(this.selections)) {
      this.selections = kept;
    }
  }

  /**
   * Matches the tab from the URL to the objects the server lists, ignoring case as the server
   * does (o=case selects Case). A name the server doesn't list (an edited URL, or an object
   * the visitor can't search) shows All; the server has already searched every object then.
   * @returns {boolean} true if the tab differs from what the URL said
   */
  matchActiveObject() {
    if (!this.activeObject) {
      return false;
    }
    const wanted = this.activeObject.toLowerCase();
    const match = this.objects.find(
      (o) => o.objectApiName.toLowerCase() === wanted
    );
    const corrected = match ? match.objectApiName : "";
    if (corrected === this.activeObject) {
      return false;
    }
    this.activeObject = corrected;
    return true;
  }

  showError(message) {
    this.errorMessage = message;
    this.status = STATUS.ERROR;
  }

  handleFacetChange(event) {
    const { objectApiName, fieldApiName, values } = event.detail;
    const selections = new Map(this.selections);
    const key = facetKey(objectApiName, fieldApiName);
    if (values?.length) {
      selections.set(key, { objectApiName, fieldApiName, values: [...values] });
    } else {
      selections.delete(key);
    }
    this.applySelections(selections);
  }

  /** Clears the filters the visitor can see; selections for other tabs' objects stay. */
  handleFacetToggle(event) {
    this.filtersExpanded = event.detail.expanded;
  }

  handleFacetClear() {
    const kept = new Map(
      [...this.selections].filter(([, selection]) => !this.inScope(selection))
    );
    this.applySelections(kept);
  }

  applySelections(selections) {
    this.selections = selections;
    this.limitPerObject = null;
    this.runSearch();
    this.writeStateToUrl();
  }

  /**
   * Adds a history entry with the current selections and tab, so the link can be shared and
   * the back button restores the previous filters and tab (replace: true corrects the current
   * entry instead). When the router reports the new
   * page reference, handlePageReference sees the same state and doesn't search again.
   */
  writeStateToUrl({ replace = false } = {}) {
    if (!this._pageReference) {
      return;
    }
    const state = { ...(this._pageReference.state ?? {}) };
    const serialized = serializeSelections(this.selections);
    if (serialized) {
      state[FACETS_PARAM] = serialized;
    } else {
      delete state[FACETS_PARAM];
    }
    if (this.activeObject) {
      state[OBJECT_PARAM] = this.activeObject;
    } else {
      delete state[OBJECT_PARAM];
    }
    this[NavigationMixin.Navigate]({ ...this._pageReference, state }, replace);
  }

  // ---- object tabs ----

  get showTabs() {
    const searched = ![STATUS.IDLE, STATUS.TOO_SHORT, STATUS.ERROR].includes(
      this.status
    );
    return this.showObjectTabs && this.objects.length > 1 && searched;
  }

  get tabs() {
    const all = { objectApiName: "", sectionLabel: tabAllLabel };
    return [all, ...this.objects].map((object, index) => {
      const selected = object.objectApiName === this.activeObject;
      return {
        id: `tab-${index}`,
        objectApiName: object.objectApiName,
        label: object.sectionLabel,
        ariaSelected: selected ? "true" : "false",
        tabIndex: selected ? "0" : "-1",
        className: selected
          ? "slds-tabs_default__item slds-is-active"
          : "slds-tabs_default__item"
      };
    });
  }

  get activeTabId() {
    return this.tabs.find((tab) => tab.ariaSelected === "true")?.id;
  }

  /** The results area is the tab panel only while tabs are shown. */
  get panelRole() {
    return this.showTabs ? "tabpanel" : undefined;
  }

  get panelLabelledBy() {
    return this.showTabs ? this.activeTabId : undefined;
  }

  handleTabClick(event) {
    this.selectTab(event.currentTarget.dataset.objectApiName);
  }

  /**
   * Arrow keys, Home and End move focus between tabs; Enter or Space (native button
   * behaviour) selects. Manual activation, because each selection runs a server search.
   */
  handleTabKeydown(event) {
    const tabs = [...this.template.querySelectorAll('[role="tab"]')];
    // Only the tab buttons in the list can take focus, so the target is always one of them.
    const current = tabs.indexOf(event.target);
    const last = tabs.length - 1;
    const next = {
      ArrowRight: current === last ? 0 : current + 1,
      ArrowLeft: current === 0 ? last : current - 1,
      Home: 0,
      End: last
    }[event.key];
    if (next !== undefined) {
      event.preventDefault();
      tabs[next].focus();
    }
  }

  /** "View all <Section>" on the All tab: switches to that object's tab. */
  handleViewAll(event) {
    const objectApiName = event.target.dataset.objectApiName;
    this._focusTab = objectApiName;
    this.selectTab(objectApiName);
  }

  selectTab(objectApiName = "") {
    if (objectApiName === this.activeObject) {
      return;
    }
    this.activeObject = objectApiName;
    this.limitPerObject = null;
    this.runSearch();
    this.writeStateToUrl();
  }

  handleLoadMore(event) {
    if (this.status !== STATUS.RESULTS) {
      return;
    }
    const objectApiName = event.target.dataset.objectApiName;
    const group = this.groups.find((g) => g.objectApiName === objectApiName);
    if (!group) {
      return;
    }
    const shown = group.results.length;
    if (this.limitPerObject === null) {
      // At the default limit, a group with more results shows exactly one page.
      this._pageSize = shown;
    }
    this.limitPerObject = Math.min(
      shown + this._pageSize,
      MAX_LIMIT_PER_OBJECT
    );
    this._loadingMoreFor = objectApiName;
    this._focusAfterLoad = { objectApiName, index: shown };
    this.runSearch({ more: true });
  }

  renderedCallback() {
    if (this._focusTab !== undefined) {
      const tab = [...this.template.querySelectorAll('[role="tab"]')].find(
        (node) => node.dataset.objectApiName === this._focusTab
      );
      if (tab) {
        this._focusTab = undefined;
        tab.focus();
      }
    }
    if (!this._focusAfterLoad || this.status !== STATUS.RESULTS) {
      return;
    }
    const { objectApiName, index } = this._focusAfterLoad;
    this._focusAfterLoad = undefined;
    // Keyboard users land on the first new result instead of losing focus with the button.
    const group = [...this.template.querySelectorAll("[data-group]")].find(
      (node) => node.dataset.group === objectApiName
    );
    group?.querySelectorAll("c-search-result-card")[index]?.focus();
  }

  /** Sanitized term from the server when available, so messages show what was searched. */
  get displayTerm() {
    return this.response?.searchTerm || this.term;
  }

  get isBrowse() {
    return this.response?.mode === MODE_BROWSE;
  }

  /**
   * On the All tab (with tabs shown) a group with more results offers "View all", which opens
   * its tab; everywhere else it offers "Load more", which grows the list in place.
   */
  get groups() {
    const loadingMore = this.status === STATUS.LOADING_MORE;
    const viewAll = this.showTabs && !this.activeObject;
    return (this.response?.groups ?? []).map((group) => {
      const more =
        Boolean(group.hasMore) && group.results.length < MAX_LIMIT_PER_OBJECT;
      return {
        ...group,
        canViewAll: viewAll && Boolean(group.hasMore),
        canLoadMore: !viewAll && more,
        viewAllLabel: formatLabel(viewAllLabel, group.sectionLabel),
        loadMoreLabel: formatLabel(loadMoreLabel, group.sectionLabel),
        isLoadingMore:
          loadingMore && this._loadingMoreFor === group.objectApiName
      };
    });
  }

  /** "Results for "term"" above the results; "Results" when browsing by filters only. */
  get heading() {
    if (!this.hasResults && this.status !== STATUS.EMPTY) {
      return "";
    }
    return this.isBrowse || !this.displayTerm
      ? headingBrowseLabel
      : formatLabel(headingLabel, this.displayTerm);
  }

  get resultCount() {
    return this.groups.reduce(
      (total, group) => total + (group.totalShown ?? group.results.length),
      0
    );
  }

  /** Server facets with "selected" taken from this component's state. */
  get panelFacets() {
    return this.facets.map((facet) => {
      const selected =
        this.selections.get(facetKey(facet.objectApiName, facet.fieldApiName))
          ?.values ?? [];
      return {
        ...facet,
        values: (facet.values ?? []).map((value) => ({
          ...value,
          selected: selected.includes(value.value)
        }))
      };
    });
  }

  /**
   * The panel stays in place on every tab once any object of the config has facets, so the
   * layout doesn't jump on a tab without them (the panel then says so).
   */
  get showFacetPanel() {
    return (
      this.showFacets &&
      (this.objects.some((object) => object.hasFacets) ||
        this.facets.some((facet) => facet.values?.length))
    );
  }

  get layoutClass() {
    if (!this.showFacetPanel) {
      return "search-results__layout";
    }
    return this.filtersExpanded
      ? "search-results__layout search-results__layout_with-facets search-results__layout_facets-open"
      : "search-results__layout search-results__layout_with-facets";
  }

  get isLoading() {
    return this.status === STATUS.LOADING;
  }

  get ariaBusy() {
    return this.isLoading || this.status === STATUS.LOADING_MORE
      ? "true"
      : "false";
  }

  get hasResults() {
    return (
      this.status === STATUS.RESULTS || this.status === STATUS.LOADING_MORE
    );
  }

  get hasError() {
    return this.status === STATUS.ERROR;
  }

  /** Text for the status line, which is also the ARIA live region. */
  get statusMessage() {
    switch (this.status) {
      case STATUS.LOADING:
        return loadingLabel;
      case STATUS.TOO_SHORT:
        return tooShortLabel;
      case STATUS.EMPTY:
        return this.emptyMessage;
      case STATUS.RESULTS:
      case STATUS.LOADING_MORE:
        return this.countMessage;
      case STATUS.IDLE:
        return this.showFacetPanel ? promptFacetsLabel : promptLabel;
      default:
        return "";
    }
  }

  get emptyMessage() {
    if (this.isBrowse) {
      return noneBrowseLabel;
    }
    return formatLabel(
      this.hasSelection ? noneFilteredLabel : noneLabel,
      this.displayTerm
    );
  }

  get countMessage() {
    const count = this.resultCount;
    if (this.isBrowse) {
      return count === 1
        ? countBrowseOneLabel
        : formatLabel(countBrowseManyLabel, count);
    }
    return count === 1
      ? formatLabel(countOneLabel, this.displayTerm)
      : formatLabel(countManyLabel, count, this.displayTerm);
  }
}
