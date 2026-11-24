import { createElement } from "lwc";
import SearchFacets, { facetKey } from "c/searchFacets";

const FACETS = [
  {
    objectApiName: "Help_Article__c",
    fieldApiName: "Category__c",
    label: "Category",
    values: [
      { value: "Getting Started", label: "Getting Started", selected: true },
      { value: "Billing", label: "Billing", selected: false }
    ]
  },
  {
    objectApiName: "Help_Article__c",
    fieldApiName: "Product__c",
    label: "Product",
    values: [
      { value: "Nimbus_Cloud", label: "Nimbus Cloud", selected: false },
      { value: "Atlas_Mobile", label: "Atlas Mobile", selected: false }
    ]
  }
];

const UNSELECTED = FACETS.map((facet) => ({
  ...facet,
  values: facet.values.map((value) => ({ ...value, selected: false }))
}));

function createFacets(facets) {
  const element = createElement("c-search-facets", { is: SearchFacets });
  element.facets = facets;
  document.body.appendChild(element);
  return element;
}

const groupsOf = (element) =>
  element.shadowRoot.querySelectorAll("lightning-checkbox-group");

const clearButton = (element) =>
  element.shadowRoot.querySelector(".search-facets__clear");

const toggleButton = (element) =>
  element.shadowRoot.querySelector(".search-facets__toggle");

const panelBody = (element) =>
  element.shadowRoot.querySelector(".search-facets__body");

const groupToggles = (element) => [
  ...element.shadowRoot.querySelectorAll(".search-facets__group-toggle")
];

const groupBodies = (element) => [
  ...element.shadowRoot.querySelectorAll(".search-facets__group-body")
];

const isCollapsed = (body) =>
  body.classList.contains("search-facets__group-body_collapsed");

// Real label text for the label whose placeholder the tests check.
jest.mock(
  "@salesforce/label/c.Search_Facet_Heading_Count",
  () => ({ default: "{0} ({1} selected)" }),
  { virtual: true }
);
jest.mock(
  "@salesforce/label/c.Search_Facets_Toggle_Count",
  () => ({ default: "Filters ({0} selected)" }),
  { virtual: true }
);

describe("c-search-facets", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders one checkbox group per facet, with options and selected values", () => {
    const element = createFacets(FACETS);

    const groups = groupsOf(element);
    expect(groups).toHaveLength(2);
    expect(groups[0].label).toBe("Category");
    expect(groups[0].options).toEqual([
      { value: "Getting Started", label: "Getting Started" },
      { value: "Billing", label: "Billing" }
    ]);
    expect(groups[0].value).toEqual(["Getting Started"]);
    expect(groups[1].label).toBe("Product");
    expect(groups[1].value).toEqual([]);
    // The heading holds the disclosure button (it names the panel).
    expect(
      element.shadowRoot.querySelector("h2 > .search-facets__toggle")
    ).not.toBeNull();
  });

  it("gives every group a name that includes the object", () => {
    const element = createFacets(FACETS);
    expect(groupsOf(element)[0].name).toBe("Help_Article__c.Category__c");
  });

  it("says there are no filters when this tab's object has none", () => {
    const element = createFacets([]);
    expect(toggleButton(element)).not.toBeNull();
    expect(groupsOf(element)).toHaveLength(0);
    expect(clearButton(element)).toBeNull();
    expect(
      element.shadowRoot.querySelector(".search-facets__none").textContent
    ).toBe("c.Search_Facets_None");
  });

  it("treats unset facets like none", () => {
    const element = createFacets(undefined);
    expect(
      element.shadowRoot.querySelector(".search-facets__none")
    ).not.toBeNull();
  });

  it("is accessible without filters, open", async () => {
    const element = createFacets([]);
    element.expanded = true;
    await Promise.resolve();
    await expect(element).toBeAccessible();
  });

  it("skips facets that have no values", () => {
    const element = createFacets([
      { ...FACETS[0], values: [] },
      { ...FACETS[1], values: undefined },
      FACETS[0]
    ]);
    expect(groupsOf(element)).toHaveLength(1);
  });

  it("reports the facet's full selection on change", () => {
    const element = createFacets(FACETS);
    const handler = jest.fn();
    element.addEventListener("facetchange", handler);

    groupsOf(element)[1].dispatchEvent(
      new CustomEvent("change", {
        detail: { value: ["Nimbus_Cloud", "Atlas_Mobile"] }
      })
    );

    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toEqual({
      objectApiName: "Help_Article__c",
      fieldApiName: "Product__c",
      values: ["Nimbus_Cloud", "Atlas_Mobile"]
    });
  });

  it("reports an empty list when the last value is unchecked", () => {
    const element = createFacets(FACETS);
    const handler = jest.fn();
    element.addEventListener("facetchange", handler);

    groupsOf(element)[0].dispatchEvent(
      new CustomEvent("change", { detail: {} })
    );

    expect(handler.mock.calls[0][0].detail.values).toEqual([]);
  });

  it("keeps 'Clear filters' focusable but aria-disabled when nothing is selected", () => {
    const element = createFacets(UNSELECTED);
    const handler = jest.fn();
    element.addEventListener("facetclear", handler);

    const button = clearButton(element);
    expect(button.textContent.trim()).toBe("c.Search_Facets_Clear");
    expect(button.getAttribute("aria-disabled")).toBe("true");
    expect(button.disabled).toBe(false);

    button.click();
    expect(handler).not.toHaveBeenCalled();
  });

  it("enables 'Clear filters' when something is selected", () => {
    expect(
      clearButton(createFacets(FACETS)).getAttribute("aria-disabled")
    ).toBe("false");
  });

  it("keeps focus on 'Clear filters' after clearing", () => {
    const element = createFacets(FACETS);
    const button = clearButton(element);
    button.focus();
    button.click();

    expect(element.shadowRoot.activeElement).toBe(button);
  });

  it("starts collapsed, behind a disclosure button", () => {
    const element = createFacets(UNSELECTED);

    const toggle = toggleButton(element);
    expect(toggle.getAttribute("aria-expanded")).toBe("false");
    expect(toggle.getAttribute("aria-controls")).toBeTruthy();
    expect(toggle.textContent.trim()).toBe("c.Search_Facets_Toggle");
    expect(panelBody(element).classList).toContain(
      "search-facets__body_collapsed"
    );
  });

  it("asks the parent to open and close the panel", async () => {
    const element = createFacets(UNSELECTED);
    const handler = jest.fn();
    element.addEventListener("facettoggle", handler);

    toggleButton(element).click();
    expect(handler.mock.calls[0][0].detail).toEqual({ expanded: true });
    // The parent owns the state: nothing opens until it sets expanded.
    expect(toggleButton(element).getAttribute("aria-expanded")).toBe("false");

    element.expanded = true;
    await Promise.resolve();
    expect(toggleButton(element).getAttribute("aria-expanded")).toBe("true");
    expect(panelBody(element).classList).not.toContain(
      "search-facets__body_collapsed"
    );

    toggleButton(element).click();
    expect(handler.mock.calls[1][0].detail).toEqual({ expanded: false });
  });

  it("shows how many values are selected on the disclosure button", () => {
    const element = createFacets(FACETS);
    expect(toggleButton(element).textContent.trim()).toBe(
      "Filters (1 selected)"
    );
  });

  it("fires facetclear when 'Clear filters' is clicked", () => {
    const element = createFacets(FACETS);
    const handler = jest.fn();
    element.addEventListener("facetclear", handler);

    clearButton(element).click();

    expect(handler).toHaveBeenCalledTimes(1);
  });

  it("is accessible", async () => {
    const element = createFacets(FACETS);
    await expect(element).toBeAccessible();
  });

  it("is accessible with the panel open and nothing selected", async () => {
    const element = createFacets(UNSELECTED);
    toggleButton(element).click();
    await Promise.resolve();
    await expect(element).toBeAccessible();
  });
});

describe("c-search-facets collapsible filters", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("gives each filter its own disclosure, open by default", () => {
    const element = createFacets(UNSELECTED);
    element.expanded = true;

    const toggles = groupToggles(element);
    const bodies = groupBodies(element);
    expect(toggles.map((t) => t.textContent.trim())).toEqual([
      "Category",
      "Product"
    ]);
    toggles.forEach((toggle, index) => {
      expect(toggle.getAttribute("aria-expanded")).toBe("true");
      expect(toggle.getAttribute("aria-controls")).toBe(bodies[index].id);
      expect(isCollapsed(bodies[index])).toBe(false);
    });
  });

  it("puts filter headings one level below the panel heading", () => {
    const element = createFacets(UNSELECTED);
    const headings = element.shadowRoot.querySelectorAll(
      ".search-facets__group-heading"
    );
    headings.forEach((heading) => {
      expect(heading.getAttribute("role")).toBe("heading");
      expect(heading.getAttribute("aria-level")).toBe("3");
    });
  });

  it("closes and reopens one filter without touching the others", async () => {
    const element = createFacets(UNSELECTED);

    groupToggles(element)[0].click();
    await Promise.resolve();

    expect(groupToggles(element)[0].getAttribute("aria-expanded")).toBe(
      "false"
    );
    expect(isCollapsed(groupBodies(element)[0])).toBe(true);
    expect(isCollapsed(groupBodies(element)[1])).toBe(false);
    // Values stay rendered while hidden, so selections are kept.
    expect(groupsOf(element)).toHaveLength(2);

    groupToggles(element)[0].click();
    await Promise.resolve();
    expect(isCollapsed(groupBodies(element)[0])).toBe(false);
  });

  it("starts every filter closed with collapseFilters, except one with a selection", () => {
    const element = createElement("c-search-facets", { is: SearchFacets });
    element.facets = FACETS;
    element.collapseFilters = true;
    document.body.appendChild(element);

    const toggles = groupToggles(element);
    // Category has a selected value, so it starts open.
    expect(toggles[0].getAttribute("aria-expanded")).toBe("true");
    expect(toggles[1].getAttribute("aria-expanded")).toBe("false");
  });

  it("shows the selection count on a closed filter's heading", async () => {
    const element = createFacets(FACETS);

    groupToggles(element)[0].click();
    await Promise.resolve();

    expect(groupToggles(element)[0].textContent.trim()).toBe(
      "Category (1 selected)"
    );
    expect(groupToggles(element)[1].textContent.trim()).toBe("Product");
  });

  it("keeps reporting changes from a filter after it is reopened", async () => {
    const element = createFacets(UNSELECTED);
    const handler = jest.fn();
    element.addEventListener("facetchange", handler);
    groupToggles(element)[1].click();
    await Promise.resolve();
    groupToggles(element)[1].click();
    await Promise.resolve();

    const product = groupsOf(element)[1];
    product.dispatchEvent(
      new CustomEvent("change", { detail: { value: ["Atlas_Mobile"] } })
    );

    expect(handler.mock.calls[0][0].detail).toEqual({
      objectApiName: "Help_Article__c",
      fieldApiName: "Product__c",
      values: ["Atlas_Mobile"]
    });
  });

  it("is accessible with a filter closed", async () => {
    const element = createFacets(FACETS);
    element.expanded = true;
    groupToggles(element)[1].click();
    await Promise.resolve();
    await expect(element).toBeAccessible();
  });
});

describe("c-search-facets with several objects", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  const statusFacet = (objectApiName, sectionLabel) => ({
    objectApiName,
    sectionLabel,
    fieldApiName: "Status__c",
    label: "Status",
    values: [
      { value: "Open", label: "Open", selected: false },
      { value: "Closed", label: "Closed", selected: false }
    ]
  });

  const TWO_OBJECTS = [
    { ...FACETS[0], sectionLabel: "Help Articles" },
    statusFacet("Help_Article__c", "Help Articles"),
    statusFacet("Case", "Cases")
  ];

  const sectionHeadings = (element) =>
    [...element.shadowRoot.querySelectorAll("h3")].map((h) =>
      h.textContent.trim()
    );

  it("puts filter headings below the object headings", () => {
    const element = createFacets(TWO_OBJECTS);
    const levels = [
      ...element.shadowRoot.querySelectorAll(".search-facets__group-heading")
    ].map((heading) => heading.getAttribute("aria-level"));
    expect(levels).toEqual(["4", "4", "4"]);
  });

  it("groups facets under each object's section label", () => {
    const element = createFacets(TWO_OBJECTS);

    expect(sectionHeadings(element)).toEqual(["Help Articles", "Cases"]);
    const articleGroups = element.shadowRoot.querySelectorAll(
      '[data-section="Help_Article__c"] lightning-checkbox-group'
    );
    const caseGroups = element.shadowRoot.querySelectorAll(
      '[data-section="Case"] lightning-checkbox-group'
    );
    expect([...articleGroups].map((g) => g.label)).toEqual([
      "Category",
      "Status"
    ]);
    expect([...caseGroups].map((g) => g.name)).toEqual(["Case.Status__c"]);
  });

  it("adds no object heading when all facets come from one object", () => {
    const element = createFacets(FACETS);
    expect(sectionHeadings(element)).toEqual([]);
  });

  it("ignores objects whose facets have no values", () => {
    const element = createFacets([
      TWO_OBJECTS[0],
      { ...TWO_OBJECTS[2], values: [] }
    ]);
    expect(sectionHeadings(element)).toEqual([]);
  });

  it("falls back to the object API name without a section label", () => {
    const element = createFacets([FACETS[0], statusFacet("Case", undefined)]);
    expect(sectionHeadings(element)).toEqual(["Help_Article__c", "Case"]);
  });

  it("reports changes from a grouped facet with its object", () => {
    const element = createFacets(TWO_OBJECTS);
    const handler = jest.fn();
    element.addEventListener("facetchange", handler);

    element.shadowRoot
      .querySelector('[data-section="Case"] lightning-checkbox-group')
      .dispatchEvent(
        new CustomEvent("change", { detail: { value: ["Open"] } })
      );

    expect(handler.mock.calls[0][0].detail).toEqual({
      objectApiName: "Case",
      fieldApiName: "Status__c",
      values: ["Open"]
    });
  });

  it("is accessible with facets from several objects", async () => {
    const element = createFacets(TWO_OBJECTS);
    await expect(element).toBeAccessible();
  });
});

describe("facetKey", () => {
  it("joins object and field", () => {
    expect(facetKey("Case", "Status")).toBe("Case.Status");
  });
});
