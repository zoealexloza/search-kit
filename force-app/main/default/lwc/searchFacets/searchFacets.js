import { LightningElement, api } from "lwc";
import clearLabel from "@salesforce/label/c.Search_Facets_Clear";
import toggleLabel from "@salesforce/label/c.Search_Facets_Toggle";
import toggleCountLabel from "@salesforce/label/c.Search_Facets_Toggle_Count";
import noneLabel from "@salesforce/label/c.Search_Facets_None";

/** Key for one facet. Field names repeat across objects, so the object is part of it. */
export function facetKey(objectApiName, fieldApiName) {
  return `${objectApiName}.${fieldApiName}`;
}

/**
 * Facet panel: one checkbox group per facet. Child of searchResults, which owns the selection
 * state and runs the search; this component only renders the facets it is given and reports
 * changes.
 *
 * The panel is a disclosure: a "Filters" button inside the h2 (aria-expanded, aria-controls)
 * shows or hides the body, on every screen size. It starts collapsed, so results come first.
 * The parent owns the open state (expanded), so it survives tab switches and the parent can
 * size its layout column; this component only asks for a change (facettoggle).
 *
 * The parent keeps the panel on every object tab once the config has facets anywhere, so the
 * layout doesn't jump. On a tab whose object has none, the body says so instead.
 *
 * "Clear filters" is always rendered and uses aria-disabled rather than
 * disappearing, so keyboard focus is never lost when it is used.
 *
 * When facets come from more than one object, they are grouped under each object's section
 * label (h3), so two facets with the same label (e.g. "Status" on two objects) can be told
 * apart. With one object there is no extra heading.
 *
 * Events (none bubbles):
 * - facettoggle: detail { expanded }, the open state the visitor asked for
 * - facetchange: detail { objectApiName, fieldApiName, values[] }, the facet's full selection
 * - facetclear: the visitor cleared every selection
 */
export default class SearchFacets extends LightningElement {
  /**
   * Facets as SearchResponseDto.FacetGroup: { objectApiName, sectionLabel, fieldApiName,
   * label, values: [{ value, label, selected }] }. selected reflects the parent's current state.
   */
  @api facets;

  /** Whether the panel is open. Owned by the parent; starts closed so results come first. */
  @api expanded = false;

  label = { clearLabel, noneLabel };

  get facetGroups() {
    return (this.facets ?? [])
      .filter((facet) => facet.values?.length)
      .map((facet) => ({
        key: facetKey(facet.objectApiName, facet.fieldApiName),
        objectApiName: facet.objectApiName,
        sectionLabel: facet.sectionLabel || facet.objectApiName,
        fieldApiName: facet.fieldApiName,
        label: facet.label,
        options: facet.values.map(({ value, label }) => ({ value, label })),
        selected: facet.values
          .filter((value) => value.selected)
          .map((value) => value.value)
      }));
  }

  /** Facets grouped by object, in server order. */
  get sections() {
    const byObject = new Map();
    for (const facet of this.facetGroups) {
      if (!byObject.has(facet.objectApiName)) {
        byObject.set(facet.objectApiName, {
          key: facet.objectApiName,
          heading: facet.sectionLabel,
          facets: []
        });
      }
      byObject.get(facet.objectApiName).facets.push(facet);
    }
    const sections = [...byObject.values()];
    const showHeading = sections.length > 1;
    return sections.map((section) => ({ ...section, showHeading }));
  }

  get hasFacets() {
    return this.facetGroups.length > 0;
  }

  get selectedCount() {
    return this.facetGroups.reduce(
      (total, facet) => total + facet.selected.length,
      0
    );
  }

  get toggleText() {
    const count = this.selectedCount;
    return count ? toggleCountLabel.replace("{0}", String(count)) : toggleLabel;
  }

  get ariaExpanded() {
    return this.expanded ? "true" : "false";
  }

  get chevronIcon() {
    return this.expanded ? "utility:chevrondown" : "utility:chevronright";
  }

  get panelClass() {
    return this.expanded
      ? "search-facets search-facets_expanded"
      : "search-facets";
  }

  get bodyClass() {
    return this.expanded
      ? "search-facets__body"
      : "search-facets__body search-facets__body_collapsed";
  }

  get clearDisabled() {
    return this.selectedCount === 0 ? "true" : "false";
  }

  handleToggle() {
    this.dispatchEvent(
      new CustomEvent("facettoggle", { detail: { expanded: !this.expanded } })
    );
  }

  handleChange(event) {
    const { objectApiName, fieldApiName } = event.target.dataset;
    this.dispatchEvent(
      new CustomEvent("facetchange", {
        detail: {
          objectApiName,
          fieldApiName,
          values: [...(event.detail.value ?? [])]
        }
      })
    );
  }

  handleClear() {
    if (this.selectedCount === 0) {
      return;
    }
    this.dispatchEvent(new CustomEvent("facetclear"));
  }
}
