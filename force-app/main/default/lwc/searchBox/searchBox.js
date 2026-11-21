import { LightningElement, api, wire } from "lwc";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import inputLabel from "@salesforce/label/c.Search_Box_Label";
import defaultPlaceholder from "@salesforce/label/c.Search_Box_Placeholder";
import buttonLabel from "@salesforce/label/c.Search_Box_Button";

/** Query-string key the search page reads. Shared contract with searchResults. */
const TERM_PARAM = "term";

/**
 * Search input for a site header or page. Searches on submit (Enter or the button), not on
 * every keystroke, and navigates to the configured search page with ?term=.
 */
export default class SearchBox extends NavigationMixin(LightningElement) {
  /** API name of the site page that holds searchResults (comm__namedPage name). */
  @api searchPageName;

  /** Placeholder text; falls back to a Custom Label so it can be translated. */
  @api placeholderText;

  label = { inputLabel, buttonLabel };
  term = "";

  get placeholder() {
    return this.placeholderText || defaultPlaceholder;
  }

  /** Prefills the box with the current term, so the header shows what was searched. */
  @wire(CurrentPageReference)
  handlePageReference(pageReference) {
    const current = pageReference?.state?.[TERM_PARAM];
    if (typeof current === "string") {
      this.term = current;
    }
  }

  handleChange(event) {
    this.term = event.target.value ?? "";
  }

  handleKeyUp(event) {
    if (event.key === "Enter") {
      this.submit();
    }
  }

  handleSubmit() {
    this.submit();
  }

  submit() {
    const term = this.term.trim();
    if (!term || !this.searchPageName) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "comm__namedPage",
      attributes: { name: this.searchPageName },
      state: { [TERM_PARAM]: term }
    });
  }
}
