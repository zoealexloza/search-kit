import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import ISSUE_OBJECT from "@salesforce/schema/Known_Issue__c";
import ISSUE_NAME from "@salesforce/schema/Known_Issue__c.Name";
import ISSUE_STATUS from "@salesforce/schema/Known_Issue__c.Status__c";
import ISSUE_SEVERITY from "@salesforce/schema/Known_Issue__c.Severity__c";
import ISSUE_PRODUCT from "@salesforce/schema/Known_Issue__c.Product__c";
import ISSUE_REPORTED from "@salesforce/schema/Known_Issue__c.Reported_Date__c";
import ISSUE_SUMMARY from "@salesforce/schema/Known_Issue__c.Summary__c";
import ISSUE_WORKAROUND from "@salesforce/schema/Known_Issue__c.Workaround__c";
import CASE_OBJECT from "@salesforce/schema/Case";
import CASE_SUBJECT from "@salesforce/schema/Case.Subject";
import CASE_NUMBER from "@salesforce/schema/Case.CaseNumber";
import CASE_STATUS from "@salesforce/schema/Case.Status";
import CASE_PRIORITY from "@salesforce/schema/Case.Priority";
import CASE_DESCRIPTION from "@salesforce/schema/Case.Description";

/** Title field and detail fields for each demo object. */
const LAYOUTS = {
  [ISSUE_OBJECT.objectApiName]: {
    title: ISSUE_NAME,
    fields: [
      ISSUE_STATUS,
      ISSUE_SEVERITY,
      ISSUE_PRODUCT,
      ISSUE_REPORTED,
      ISSUE_SUMMARY,
      ISSUE_WORKAROUND
    ]
  },
  [CASE_OBJECT.objectApiName]: {
    title: CASE_SUBJECT,
    fields: [CASE_NUMBER, CASE_STATUS, CASE_PRIORITY, CASE_DESCRIPTION]
  }
};

/**
 * Demo only (never packaged): shows a Known Issue or Case on the support portal's record
 * pages, so search result links land on something readable. Uses the UI API through
 * lightning-record-view-form, which enforces the visitor's object, field and record access.
 */
export default class SupportRecordDetail extends LightningElement {
  /** Bound to {!recordId} on the record page. */
  @api recordId;

  /** Known_Issue__c or Case; set per record page in the site metadata. */
  @api objectApiName;

  /** The title field is read through getRecord so the heading is never rendered empty. */
  @wire(getRecord, { recordId: "$recordId", fields: "$titleFields" })
  record;

  get layout() {
    return LAYOUTS[this.objectApiName];
  }

  get hasLayout() {
    return Boolean(this.recordId && this.layout);
  }

  get titleFields() {
    return this.layout ? [this.layout.title] : undefined;
  }

  get title() {
    return this.record?.data
      ? getFieldValue(this.record.data, this.layout.title)
      : undefined;
  }

  get detailFields() {
    return this.layout.fields.map((field) => field.fieldApiName);
  }
}
