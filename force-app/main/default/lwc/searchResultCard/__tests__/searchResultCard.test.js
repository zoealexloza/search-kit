import { createElement } from "lwc";
import SearchResultCard from "c/searchResultCard";
import {
  getGenerateUrlCalls,
  getNavigateCalls,
  resetNavigationMock
} from "lightning/navigation";

const RESULT = {
  recordId: "a00000000000001AAA",
  title: "Reset your password",
  score: 61,
  details: [
    { label: "Category", value: "Getting Started" },
    { label: "Product", value: "Nimbus Cloud; Atlas Mobile" }
  ]
};

const RECORD_PAGE = {
  type: "standard__recordPage",
  attributes: {
    recordId: RESULT.recordId,
    objectApiName: "Help_Article__c",
    actionName: "view"
  }
};

/** Resolves pending promises (GenerateUrl) and the re-render that follows. */
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function createCard(result = RESULT) {
  const element = createElement("c-search-result-card", {
    is: SearchResultCard
  });
  element.result = result;
  element.objectApiName = "Help_Article__c";
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

describe("c-search-result-card", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    resetNavigationMock();
  });

  it("moves focus to the title link when focus() is called", async () => {
    const element = await createCard();
    element.focus();

    expect(element.shadowRoot.activeElement).toBe(
      element.shadowRoot.querySelector("h4 a")
    );
  });

  it("focuses the link once its URL arrives when focus() is called early", async () => {
    const element = createElement("c-search-result-card", {
      is: SearchResultCard
    });
    element.result = RESULT;
    element.objectApiName = "Help_Article__c";
    document.body.appendChild(element);
    element.focus();
    expect(element.shadowRoot.activeElement).toBeNull();

    await flushPromises();
    expect(element.shadowRoot.activeElement).toBe(
      element.shadowRoot.querySelector("h4 a")
    );
  });

  it("renders the title as a link to the record page", async () => {
    const element = await createCard();
    const link = element.shadowRoot.querySelector("h4 a");

    expect(link.textContent).toBe("Reset your password");
    expect(link.getAttribute("href")).toBe(
      "/support/detail/a00000000000001AAA"
    );
    expect(getGenerateUrlCalls()).toEqual([RECORD_PAGE]);
  });

  it("renders each detail as a label and value", async () => {
    const element = await createCard();
    const labels = [...element.shadowRoot.querySelectorAll("dt")].map(
      (node) => node.textContent
    );
    const values = [...element.shadowRoot.querySelectorAll("dd")].map(
      (node) => node.textContent
    );

    expect(labels).toEqual(["Category", "Product"]);
    expect(values).toEqual(["Getting Started", "Nimbus Cloud; Atlas Mobile"]);
  });

  it("leaves out the detail list when there are no details", async () => {
    const element = await createCard({ ...RESULT, details: [] });

    expect(element.shadowRoot.querySelector("dl")).toBeNull();
  });

  it("renders markup in record data as plain text", async () => {
    const element = await createCard({
      ...RESULT,
      title: '<img src=x onerror="alert(1)">',
      details: [{ label: "Summary", value: "<b>bold</b>" }]
    });

    expect(element.shadowRoot.querySelector("img")).toBeNull();
    expect(element.shadowRoot.querySelector("b")).toBeNull();
    expect(element.shadowRoot.querySelector("h4 a").textContent).toBe(
      '<img src=x onerror="alert(1)">'
    );
  });

  it("navigates in-app on a plain click", async () => {
    const element = await createCard();
    const click = new MouseEvent("click", { bubbles: true, cancelable: true });
    element.shadowRoot.querySelector("h4 a").dispatchEvent(click);

    expect(click.defaultPrevented).toBe(true);
    expect(getNavigateCalls()).toEqual([
      { pageReference: RECORD_PAGE, replace: undefined }
    ]);
  });

  it("leaves ctrl/cmd-clicks to the browser (open in new tab)", async () => {
    const element = await createCard();
    const link = element.shadowRoot.querySelector("h4 a");
    const ctrlClick = new MouseEvent("click", {
      bubbles: true,
      cancelable: true,
      ctrlKey: true
    });
    const metaClick = new MouseEvent("click", {
      bubbles: true,
      cancelable: true,
      metaKey: true
    });
    // Runs after the component's handler: records whether it let the click through, then
    // stops jsdom from following the link (it can't navigate).
    const preventedByComponent = [];
    link.addEventListener("click", (event) => {
      preventedByComponent.push(event.defaultPrevented);
      event.preventDefault();
    });
    link.dispatchEvent(ctrlClick);
    link.dispatchEvent(metaClick);

    expect(preventedByComponent).toEqual([false, false]);
    expect(getNavigateCalls()).toHaveLength(0);
  });

  it("regenerates the link when the result changes", async () => {
    const element = await createCard();
    element.result = { ...RESULT, recordId: "a00000000000002AAA" };
    await flushPromises();

    expect(element.shadowRoot.querySelector("h4 a").getAttribute("href")).toBe(
      "/support/detail/a00000000000002AAA"
    );
    expect(getGenerateUrlCalls()).toHaveLength(2);
  });

  it("is accessible", async () => {
    const element = await createCard();
    await expect(element).toBeAccessible();
  });

  it("shows the object icon before the title when one is set", async () => {
    const plain = await createCard();
    expect(plain.shadowRoot.querySelector("lightning-icon")).toBeNull();

    const element = createElement("c-search-result-card", {
      is: SearchResultCard
    });
    element.result = RESULT;
    element.iconName = "standard:article";
    document.body.appendChild(element);
    await flushPromises();

    const icon = element.shadowRoot.querySelector("h4 lightning-icon");
    expect(icon.iconName).toBe("standard:article");
    await expect(element).toBeAccessible();
  });
});
