import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";

/**
 * One search result: a title linking to the record page, plus up to three detail fields.
 * All values arrive pre-formatted from Apex and are rendered as text only.
 *
 * The title is a real link (href from GenerateUrl), so middle-click, "open in new tab" and
 * screen-reader link lists work. A plain click navigates through NavigationMixin instead, so
 * the site stays a single-page app.
 */
export default class SearchResultCard extends NavigationMixin(
  LightningElement
) {
  /** { recordId, title, details: [{ label, value }] } from SearchResponseDto.Result. */
  @api result;

  /** Object API name of the result's group; helps the site resolve the record page. */
  @api objectApiName;

  /** SLDS icon of the result's object (Icon_Name__c), shown before the title. Decorative. */
  @api iconName;

  url;
  _generatedFor;
  _focusPending = false;

  get pageReference() {
    return {
      type: "standard__recordPage",
      attributes: {
        recordId: this.result?.recordId,
        objectApiName: this.objectApiName,
        actionName: "view"
      }
    };
  }

  get details() {
    return (this.result?.details ?? []).map((detail, index) => ({
      key: `${index}-${detail.label}`,
      label: detail.label,
      value: detail.value
    }));
  }

  get hasDetails() {
    return this.details.length > 0;
  }

  renderedCallback() {
    if (this._focusPending && this.url) {
      this._focusPending = false;
      this.template.querySelector("a")?.focus();
    }
    // Regenerate the link only when the record changes, not on every render.
    const recordId = this.result?.recordId;
    if (recordId && recordId !== this._generatedFor) {
      this._generatedFor = recordId;
      this[NavigationMixin.GenerateUrl](this.pageReference).then((url) => {
        if (this._generatedFor === recordId) {
          this.url = url;
        }
      });
    }
  }

  /**
   * Moves focus to the title link (used after "Load more"). A link without an href can't take
   * focus, so if GenerateUrl hasn't resolved yet, focus moves once it has.
   */
  @api
  focus() {
    if (this.url) {
      this.template.querySelector("a")?.focus();
    } else {
      this._focusPending = true;
    }
  }

  handleClick(event) {
    // Let the browser handle new-tab / new-window clicks.
    if (event.ctrlKey || event.metaKey || event.shiftKey || event.button > 0) {
      return;
    }
    event.preventDefault();
    this[NavigationMixin.Navigate](this.pageReference);
  }
}
