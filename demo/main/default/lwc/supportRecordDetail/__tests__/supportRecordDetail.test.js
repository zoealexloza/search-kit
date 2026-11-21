import { createElement } from "lwc";
import SupportRecordDetail from "c/supportRecordDetail";
import { getRecord } from "lightning/uiRecordApi";

const ISSUE_RECORD = {
  apiName: "Known_Issue__c",
  id: "a00000000000001AAA",
  fields: {
    Name: {
      value: "Password reset emails delayed for Outlook.com addresses",
      displayValue: null
    }
  }
};

/** Resolves pending promises and the re-render that follows. */
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function createDetail(props) {
  const element = createElement("c-support-record-detail", {
    is: SupportRecordDetail
  });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const fieldNames = (element) =>
  [...element.shadowRoot.querySelectorAll("lightning-output-field")].map(
    (field) => field.fieldName
  );

const heading = (element) => element.shadowRoot.querySelector("h1");

describe("c-support-record-detail", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows a known issue's detail fields in a record view form", () => {
    const element = createDetail({
      recordId: "a00000000000001AAA",
      objectApiName: "Known_Issue__c"
    });

    const form = element.shadowRoot.querySelector("lightning-record-view-form");
    expect(form.recordId).toBe("a00000000000001AAA");
    expect(form.objectApiName).toBe("Known_Issue__c");
    expect(fieldNames(element)).toEqual([
      "Status__c",
      "Severity__c",
      "Product__c",
      "Reported_Date__c",
      "Summary__c",
      "Workaround__c"
    ]);
  });

  it("asks getRecord for the object's title field", async () => {
    createDetail({ recordId: "500000000000001AAA", objectApiName: "Case" });
    await flushPromises();

    const config = getRecord.getLastConfig();
    expect(config.recordId).toBe("500000000000001AAA");
    expect(config.fields.map((field) => field.fieldApiName)).toEqual([
      "Subject"
    ]);
  });

  it("shows the title as the page heading once the record loads", async () => {
    const element = createDetail({
      recordId: "a00000000000001AAA",
      objectApiName: "Known_Issue__c"
    });
    expect(heading(element)).toBeNull();

    getRecord.emit(ISSUE_RECORD);
    await flushPromises();

    expect(heading(element).textContent).toBe(
      "Password reset emails delayed for Outlook.com addresses"
    );
  });

  it("shows no heading when the record can't be read", async () => {
    const element = createDetail({
      recordId: "a00000000000001AAA",
      objectApiName: "Known_Issue__c"
    });

    getRecord.error();
    await flushPromises();

    expect(heading(element)).toBeNull();
  });

  it("shows a case's detail fields", () => {
    const element = createDetail({
      recordId: "500000000000001AAA",
      objectApiName: "Case"
    });

    expect(fieldNames(element)).toEqual([
      "CaseNumber",
      "Status",
      "Priority",
      "Description"
    ]);
  });

  it("renders nothing for an object it has no layout for", () => {
    const element = createDetail({
      recordId: "001000000000001AAA",
      objectApiName: "Account"
    });

    expect(
      element.shadowRoot.querySelector("lightning-record-view-form")
    ).toBeNull();
  });

  it("renders nothing without a record id (e.g. in Experience Builder)", () => {
    const element = createDetail({ objectApiName: "Case" });

    expect(
      element.shadowRoot.querySelector("lightning-record-view-form")
    ).toBeNull();
  });

  it("is accessible before and after the record loads", async () => {
    const element = createDetail({
      recordId: "a00000000000001AAA",
      objectApiName: "Known_Issue__c"
    });
    await expect(element).toBeAccessible();

    getRecord.emit(ISSUE_RECORD);
    await flushPromises();
    await expect(element).toBeAccessible();
  });
});
