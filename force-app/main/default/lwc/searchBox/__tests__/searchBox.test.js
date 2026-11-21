import { createElement } from "lwc";
import SearchBox from "c/searchBox";
import {
  CurrentPageReference,
  getNavigateCalls,
  resetNavigationMock
} from "lightning/navigation";

jest.mock(
  "@salesforce/label/c.Search_Box_Placeholder",
  () => ({ default: "Search..." }),
  { virtual: true }
);

function createSearchBox(props = {}) {
  const element = createElement("c-search-box", { is: SearchBox });
  Object.assign(element, { searchPageName: "Search__c", ...props });
  document.body.appendChild(element);
  return element;
}

function getInput(element) {
  return element.shadowRoot.querySelector("lightning-input");
}

function typeTerm(element, value) {
  const input = getInput(element);
  input.value = value;
  input.dispatchEvent(new CustomEvent("change"));
}

function pressKey(element, key) {
  getInput(element).dispatchEvent(new KeyboardEvent("keyup", { key }));
}

function clickButton(element) {
  element.shadowRoot.querySelector("lightning-button").click();
}

describe("c-search-box", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    resetNavigationMock();
  });

  it("navigates to the search page with the trimmed term on Enter", async () => {
    const element = createSearchBox();
    typeTerm(element, "  password reset  ");
    pressKey(element, "Enter");
    await Promise.resolve();

    expect(getNavigateCalls()).toEqual([
      {
        pageReference: {
          type: "comm__namedPage",
          attributes: { name: "Search__c" },
          state: { term: "password reset" }
        },
        replace: undefined
      }
    ]);
  });

  it("navigates when the button is clicked", () => {
    const element = createSearchBox({ searchPageName: "Find__c" });
    typeTerm(element, "invoice");
    clickButton(element);

    const [call] = getNavigateCalls();
    expect(call.pageReference.attributes.name).toBe("Find__c");
    expect(call.pageReference.state.term).toBe("invoice");
  });

  it("ignores keys other than Enter", () => {
    const element = createSearchBox();
    typeTerm(element, "sync");
    pressKey(element, "a");

    expect(getNavigateCalls()).toHaveLength(0);
  });

  it("does not navigate for a blank term", () => {
    const element = createSearchBox();
    typeTerm(element, "   ");
    clickButton(element);

    expect(getNavigateCalls()).toHaveLength(0);
  });

  it("does not navigate when no search page is configured", () => {
    const element = createSearchBox({ searchPageName: "" });
    typeTerm(element, "export");
    clickButton(element);

    expect(getNavigateCalls()).toHaveLength(0);
  });

  it("prefills the term from the current page URL", async () => {
    const element = createSearchBox();
    CurrentPageReference.emit({ state: { term: "export" } });
    await Promise.resolve();

    expect(getInput(element).value).toBe("export");
  });

  it("keeps an empty box when the page has no term", async () => {
    const element = createSearchBox();
    CurrentPageReference.emit({ state: {} });
    await Promise.resolve();

    expect(getInput(element).value).toBe("");
  });

  it("uses the default placeholder unless one is configured", async () => {
    const element = createSearchBox();
    expect(getInput(element).placeholder).toBe("Search...");

    element.placeholderText = "Search help articles";
    await Promise.resolve();
    expect(getInput(element).placeholder).toBe("Search help articles");
  });

  it("gives the input an accessible label inside a search landmark", () => {
    const element = createSearchBox();
    const input = getInput(element);

    expect(input.label).toBe("c.Search_Box_Label");
    expect(input.variant).toBe("label-hidden");
    expect(input.type).toBe("search");
    expect(element.shadowRoot.querySelector('[role="search"]')).not.toBeNull();
  });

  it("is accessible", async () => {
    const element = createSearchBox();
    await expect(element).toBeAccessible();
  });
});
