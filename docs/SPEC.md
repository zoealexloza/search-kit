# Site Search Kit — Spec (v1 complete; v2 in §10)

> Progress and findings: `docs/PROGRESS.md`.

## 1. Problem

Standard Experience Cloud search is hard to tune. Admins can't easily control which records appear or rank first based on field values (e.g., "only published resources," "featured items first"). The main alternative (Coveo) is a full paid platform. There's room for a **free, lightweight, admin-configured** search component that runs entirely inside Salesforce.

## 2. Goals for v1

**Site visitors** can:

- Type in a search box (usually in the site header) and land on a results page.
- See results grouped by object, each showing a title, up to 3 detail fields, and a link to the record's detail page.
- Narrow results with facets (picklist and checkbox fields).
- Load more results.

**Admins** can, with no code:

- Choose which objects are searchable and which fields display.
- Define **fixed filters** by field value (structured rules, not raw SOQL).
- Define **boost rules** by field value that re-rank results.
- Choose which fields appear as facets.
- Select which configuration a component uses from the Experience Builder property panel.

**The headline differentiator** is boost rules: SOSL doesn't let you control ranking, so the service takes SOSL's relevance order and re-ranks it in Apex using admin-defined rules.

### Non-goals for v1 (put ideas in `docs/BACKLOG.md`)

Knowledge articles (separate SOSL rules — v2), typo tolerance/synonyms, search analytics, multi-language, in-site config editing UI, Agentforce action (planned v2 headline), Data Cloud.

## 3. Platform decisions

- **Site type:** build and demo on **LWR** first; verify on an **Aura** site before release (many client sites are still Aura). Components must target both.
- **Package:** unlocked package, no namespace, for v1 (GitHub install link). Avoid anything that would make a later move to another package type hard (e.g., hardcoded API-name strings in LWC where schema imports work).
- **Configuration storage:** Custom Metadata Types (deployable, packageable, `getAll()` doesn't consume query limits).

## 4. Data model (Custom Metadata Types)

**Object and field references are Text fields holding API names, validated in Apex at runtime** (must exist in `Schema` describe, be accessible to the running user, and be referenced by the active config). Links between the config types themselves use **metadata relationship fields** (e.g. `Search_Object__c → Search_Config`).

> **Decision (2026-11-13):** the original plan used Entity Definition / Field Definition relationship fields so admins could pick from lists. Testing in M1 showed that `getAll()` returns durable IDs (not API names) for custom objects and fields, and SOQL on the type silently drops records whose Field Definition field points at a custom field. Resolving the IDs would need `EntityDefinition`/`FieldDefinition` queries on every search, which are unlikely to work for guest users in user mode. Text fields keep config loading to `getAll()` only and match the Filter/Boost/Facet types. Details in `docs/PROGRESS.md`.

### `Search_Config__mdt`

| Field                     | Type      | Notes                                    |
| ------------------------- | --------- | ---------------------------------------- |
| `Label` / `DeveloperName` | std       | Shown in the Experience Builder picklist |
| `Description__c`          | Text Area |                                          |
| `Results_Per_Object__c`   | Number    | Default 10; max 50                       |
| `Is_Active__c`            | Checkbox  |                                          |

### `Search_Object__mdt`

| Field                                     | Type                                  | Notes                              |
| ----------------------------------------- | ------------------------------------- | ---------------------------------- |
| `Search_Config__c`                        | Metadata Relationship → Search_Config |                                    |
| `Object__c`                               | Text (validated)                      | Object API name, e.g. `Case`       |
| `Title_Field__c`                          | Text (validated)                      | Field API name on `Object__c`      |
| `Detail_Field_1__c` … `Detail_Field_3__c` | Text (validated)                      | Optional                           |
| `Icon_Name__c`                            | Text                                  | SLDS icon, e.g. `standard:article` |
| `Section_Label__c`                        | Text                                  | Heading for this group of results  |
| `Sort_Order__c`                           | Number                                | Order of object groups on the page |
| `Is_Active__c`                            | Checkbox                              |                                    |

### `Search_Filter_Rule__mdt` (fixed filters — always applied)

| Field              | Type                                  | Notes                                                                                                                                                                   |
| ------------------ | ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Search_Object__c` | Metadata Relationship → Search_Object |                                                                                                                                                                         |
| `Field__c`         | Text (validated)                      | API name on the parent object                                                                                                                                           |
| `Operator__c`      | Picklist                              | `equals`, `not_equals`, `includes` (multi-select), `greater_than`, `less_than`, `is_true`, `is_false`; since M8 `is_blank`, `is_not_blank`, `in` (`;`-separated values) |
| `Value__c`         | Text                                  | Type-checked against field type at runtime. Date fields also accept relative dates (M8, see §10.3)                                                                      |

v1 combines all filter rules on an object with **AND**.

### `Search_Boost_Rule__mdt`

| Field              | Type                                  | Notes                                              |
| ------------------ | ------------------------------------- | -------------------------------------------------- |
| `Search_Object__c` | Metadata Relationship → Search_Object |                                                    |
| `Field__c`         | Text (validated)                      |                                                    |
| `Operator__c`      | Picklist                              | Same set as filter rules, plus `contains` for text |
| `Value__c`         | Text                                  |                                                    |
| `Points__c`        | Number                                | Can be negative (demote)                           |

### `Search_Facet__mdt`

| Field              | Type                                  | Notes                                                   |
| ------------------ | ------------------------------------- | ------------------------------------------------------- |
| `Search_Object__c` | Metadata Relationship → Search_Object |                                                         |
| `Field__c`         | Text (validated)                      | Picklist, multi-select picklist, or checkbox only in v1 |
| `Label__c`         | Text                                  | Optional override of field label                        |
| `Sort_Order__c`    | Number                                |                                                         |

## 5. Apex architecture

```
SiteSearchController        @AuraEnabled entry points only; thin; catches and maps exceptions
 └─ SearchService           orchestrates a search request
     ├─ SearchConfigProvider     loads + caches config (getAll()), returns typed config objects
     ├─ SchemaValidator          validates object/field names, field types, accessibility
     ├─ SearchQueryBuilder       builds SOSL (term ≥ 2 chars) or SOQL fallback (facet-only browse)
     ├─ BoostRuleEngine          scores + re-ranks results
     ├─ FacetService             facet definitions + picklist values via describe
     └─ SearchResultMapper       records → DTOs, values formatted for the user's locale
```

Supporting types (added in M2): `SearchConfig` (typed, unvalidated config), `SearchTarget` (an object that passed validation: describe results only, never config text), `SiteSearchException` (user-safe errors with Custom Label messages), `SearchRequestDto` / `SearchResponseDto`.

### Request / response

- **Request DTO:** `configName`, `searchTerm`, `selectedFacets`, `limitPerObject`. `selectedFacets` is a list of `{ objectApiName, fieldApiName, values[] }` rather than a nested map: a flat list of typed objects deserializes predictably from LWC and is simpler to validate (decided in M2). Values within a facet are ORed; facets are ANDed. Since M8.5 also `objectApiNames` (optional scope, from an object tab; unknown names ignored, none left means all objects).
- **Response DTO:** `searchTerm` (sanitized), `mode` (`search` / `browse` / `none`), list of object groups → `{ objectApiName, sectionLabel, iconName, totalShown, hasMore, results[] }`; each result → `{ recordId, title, details[] (label + formatted value), score }`; plus `facets[]` → `{ objectApiName, sectionLabel, fieldApiName, label, values[] { value, label, selected } }` (`sectionLabel` added in M7). Since M8.5 also `objects[]` → `{ objectApiName, sectionLabel, iconName }`: every object the visitor can search, whatever the scope, for the tabs; `facets` cover only the searched objects. Only groups with results are returned; facets are returned for every searchable object, even when no query ran.
- **Facet values and filter rules (M8):** a facet doesn't offer values that a filter rule on the same field rules out (`equals` / `in` keep only their values, `not_equals` removes one, `is_true` / `is_false` keep one, `is_blank` removes all and the facet is hidden). Multi-select facets aren't narrowed. Selections of removed values are ignored.
- **Facet scope:** a selection narrows only its own object. With a term, other objects are still searched; in browse mode only objects with a selection are queried.
- **Invalid config handling:** an invalid object or title field skips the object; an invalid **filter** rule also skips the object (fail closed, so a typo can't expose Draft records); an invalid detail field, boost rule or facet skips only that entry.

### Search flow

1. Load active config by `configName`; reject unknown/inactive configs.
2. Validate every object/field referenced in config against `Schema` + accessibility. Skip (and log) invalid entries rather than failing the whole search.
3. If `searchTerm` ≥ 2 chars after sanitizing → one SOSL query: `FIND '<term>' IN ALL FIELDS RETURNING Obj1(fields WHERE filters LIMIT n), Obj2(...)`. Fields returned = title + details + any boost-rule fields + facet fields.
   SOSL can't bind a variable number of values, so SOSL filter values are written as literals after type validation and escaping; SOQL binds every value.
   Else if facets are selected → SOQL per object via `Database.queryWithBinds` (browse mode).
   Else → empty response (no "return everything" by default).
4. Run in **user mode** (`AccessLevel.USER_MODE`).
5. Re-rank per object: `score = baseScore + sum(matching boost points)`, where `baseScore = (resultCount - sosIndex)` so SOSL relevance is the tiebreaker baseline. Stable sort descending. Each query fetches a candidate pool of `min(3 × limit, 200) + 1` rows (since M7; v1 fetched `limit + 1`). All fetched rows are ranked before the list is cut to `limit`, and `hasMore` is set when more rows were fetched than shown. For SOSL the per-object pool shrinks so all objects together stay within SOSL's 2,000-row total, but never below `limit + 1`. "Load more" re-runs the search with a larger `limitPerObject` (capped at 200); since M7 the component appends the new results below the ones already shown, so a record the visitor has seen never moves.
6. Map to DTOs; format values (dates, picklist labels) server-side.

### Boost scoring note

Keep the scoring formula in one method with a clear docblock — it's a talking point in interviews. Unit-test it with table-style cases.

## 6. LWC components

| Component          | Purpose                                                                                                                                            | Targets                                                   |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| `searchBox`        | Input + submit; navigates to the search page with `?term=`                                                                                         | `lightningCommunity__Page`, `lightningCommunity__Default` |
| `searchResults`    | Reads `term` from `CurrentPageReference.state`; calls Apex; renders groups; "Load more"                                                            | same                                                      |
| `searchFacets`     | Facet panel; emits selection changes to `searchResults` (parent/child composition or a shared container — choose the simpler one and document why) | child of `searchResults` or same targets                  |
| `searchResultCard` | One result row/card                                                                                                                                | internal                                                  |

> **Decision (M4, 2026-11-14): `searchFacets` is a child of `searchResults`.** `searchResults` already receives the facet definitions in the search response and owns the term, so it also owns the selections: the child renders what it is given and fires `facetchange` / `facetclear`. A shared container or message channel would add a second component for admins to place and keep in sync for no v1 benefit. `searchFacets` is not exposed in Builder; `showFacets` turns the panel on or off.
>
> Behavior: a new term clears the selections and "Load more"; a facet change resets "Load more" to the config's page size. Since M7, selections are written to the URL (`?f=`) and read on load, so a filtered link can be shared and back/forward restore it; a term from `searchBox` arrives without `f`, so a new search still starts unfiltered. When more than one object has facets, the panel groups them under each object's section label (M7). Facet panel left of the results from 48em up, stacked above them below that.

Property panel (`js-meta.xml` → `targetConfigs`):

- `searchBox`: `searchPageName` (API name of the results page), `placeholderText`.
- `searchResults`: `configName` (use a **dynamic picklist** via `VisualEditor.DynamicPickList` Apex class listing active configs), `showFacets` (boolean), `showObjectTabs` (boolean, M8.5).

Navigation: `NavigationMixin` with `standard__recordPage` for result links; `comm__namedPage` for the search page.

UX requirements: debounced input is not needed (search on submit); clear loading, empty ("No results for …"), and error states; result count announced via ARIA live region; works at mobile widths.

## 7. Demo environment

- **Scenario (decided 2026-11-13):** a fictional **customer support portal** for a software company with three products (Nimbus Cloud, Atlas Mobile, Beacon Analytics).
  - `Help_Article__c` — self-service help content (Article Title = Name, Summary long text, Category picklist, Product multi-select, Status picklist, Featured checkbox, Published Date). A custom object stands in for Knowledge, which is a v2 goal.
  - Standard `Case` — shows that search respects sharing: guests see no cases, a logged-in customer sees only their own.
- **Demo metadata lives in `demo/`, not `force-app/`.** `force-app/` is what gets packaged (M6); `demo/` (demo object, sample config records, demo permission sets) is a second, never-packaged package directory.
- Sample data: ~60 records via `sf data import tree` (`scripts/generate-sample-data.js` produces `data/`). Built around four demo terms — "password", "invoice", "sync", "export" — so that for each term a featured or Getting Started article visibly jumps above a stronger plain match, and a Draft/Archived match is visibly filtered out.
- Sample config records: one "Support Portal Search" config with a filter rule (`Status__c = Published`), three boost rules (`Featured__c` is true +50, `Category__c = Getting Started` +10, from M8 `Published_Date__c greater_than LAST_N_DAYS:30` +5), and facets on Category and Product. Cases are a second Search Object ("My Cases") with, from M7, a Status facet (so a logged-in customer sees facets from two objects) and, from M8, a filter `Status in New;Working;Escalated;Closed` (every status; it shows the `in` operator and keeps cases with a status added later out until an admin lists it). `scripts/setup-demo-users.js` moves three articles' publish dates into the last 30 days so the recent boost always has something to show.
- An LWR site ("Support Portal", path `/support`, public access enabled) in the scratch org with a header search box and a search page (search UI arrives in M3). Scratch org definition enables the `Communities` feature plus `communitiesSettings.enableNetworksEnabled` and `experienceBundleSettings.enableExperienceBundleMetadata` (verified in a scratch org, see `docs/PROGRESS.md`).
- Permission sets:
  - `Site_Search_Kit_Admin` (packaged) — access to the config metadata types (and from M2 the Experience Builder Apex classes). Does **not** grant Customize Application, which editing config records in Setup also requires.
  - `Site_Search_Kit_User` (packaged) — Apex class access for site users (classes added in M2). Object/field access to searched objects is the subscriber org's job.
  - `Support_Demo_User` / `Support_Demo_Admin` (demo only) — read / full access to the demo objects.
- Document guest user setup in the README.

## 8. Milestones

Each milestone ends with: acceptance criteria met, tests green, Code Analyzer clean or findings documented, `docs/PROGRESS.md` updated.

### M1 — Foundation

- SFDX project, `.gitignore`, ESLint/Prettier/Jest config, `config/project-scratch-def.json` with Experience Cloud enabled.
- All five Custom Metadata types and fields.
- Demo objects, sample data plan, sample config records, permission sets.
- An LWR site created in the scratch org (manual steps documented in `docs/SETUP.md` if they can't be scripted).
- **Done when:** a fresh scratch org can be built from the README steps in < 15 minutes, with demo data and config present.

### M2 — Apex search service

- All classes in §5, request/response DTOs, controller.
- **Done when:** tests cover SOSL path, SOQL browse path, filters, boost re-ranking, facet values, invalid config entries, inaccessible fields/objects, and injection-style inputs (`'`, `\`, SOSL reserved chars, very long terms). ≥ 90% coverage.

### M3 — Core LWCs

- `searchBox`, `searchResults`, `searchResultCard`, dynamic picklist for config selection, navigation.
- **Done when:** on the demo site, searching from the header lands on results grouped by object, links open record pages, and the property panel works. Jest tests pass.

### M4 — Facets + states

- `searchFacets`, browse mode, "Load more", loading/empty/error states.
- **Done when:** selecting facets narrows results with and without a search term; all states render correctly; Jest tests cover them.

### M5 — Guest users, accessibility, polish

- Configure and test as **guest user** and **logged-in external user** (guest profile object/field access, guest sharing rules, Apex class access). Document every required step in the README.
- Accessibility pass (keyboard, focus, ARIA, contrast); mobile layout.
- Verify components on an **Aura** site.
- **Done when:** the demo works end-to-end for an unauthenticated visitor, and README "Guest user setup" is complete and tested from scratch.

### M6 — Package and README

- Unlocked package + version; install link in README.
- README: problem, GIF/screenshots, features, architecture diagram (Mermaid), boost scoring explanation, install + setup, guest user setup, security notes, roadmap.
- Final Code Analyzer run with results summarized in `docs/SECURITY.md`.
- **Done when:** a stranger can install the package into a fresh org and configure a working search by following the README alone.

## 9. Open decisions (owner)

- ~~Final product name~~: decided **Search Kit** (owner, 2026-11-20). The working name was Site Search Kit; permission set, component and v1 package labels still use it.
- ~~Demo scenario~~ — decided: customer support portal (2026-11-13).
- ~~License~~ — decided: MIT (2026-11-13).
- ~~How the service reads object/field references from config~~ — decided: validated Text fields (2026-11-13, see §4).

## 10. v2

> Status: **approved by the owner, 2026-11-15**, including the M8 operator values and the M9 `Allow_Agent_Access__c` field. The M10 data category fields were approved on 2026-11-20 after the spike (`docs/PROGRESS.md`). Anything beyond this section goes to `docs/BACKLOG.md`.

### 10.1 Goals for v2

- **Agentforce:** an agent can answer questions using the same search config (objects, filters, boosts) as the site, with the same security model.
- **Knowledge:** Salesforce Knowledge articles can be a searchable object next to custom and standard objects.
- **Better results and filters:** boosted records can reach page 1 even when SOSL ranks them low; filtered results can be shared by URL; richer rule operators.

### 10.2 Non-goals for v2

Typo tolerance / synonyms, search analytics, multi-language UI, in-site config editor, Data Cloud. Facet value counts and prefix search stay in `docs/BACKLOG.md` (see 10.5).

### 10.3 Milestones

Each milestone keeps the v1 rules (§8): acceptance criteria met, tests green, Code Analyzer clean or findings documented, `docs/PROGRESS.md` updated. Apex tests use only standard objects (they must run in the packaging org); Knowledge tests are the exception (see M10).

#### M7: Ranking and facet polish (no data model change)

- **Larger candidate pool:** each object's query fetches `min(3 × limit, 200)` rows (multiplier as a constant, not config) before re-ranking, then cuts to `limit`. `hasMore` = more rows were fetched than shown. Check SOSL's 2,000-row total across objects, and keep "Load more" stable: a record already shown never moves to a later page.
- **Facet selections in the URL:** `searchResults` writes selections to the page state (`?term=…&f=…`) and reads them on load, so a filtered link can be shared and the back button restores it. URL values are untrusted input: they go through the existing server-side validation, and unknown facets and values are dropped silently.
- **Facet labels across objects:** `FacetGroup` gets the object's section label; the panel groups facets under it when more than one object has facets.
- **Done when:** a Featured article at SOSL position 25 shows on page 1 with page size 10 (Apex test with `Test.setFixedSearchResults`); a filtered results URL opened in a new tab shows the same results and facets; back/forward restore selections; a tampered `f=` value is ignored (Jest + Apex tests); two "Status" facets from different objects are distinguishable on the demo site.

#### M8: Richer rules

> **Closed 2026-11-20** (owner checked the site). Built as planned. Decisions made while building: a relative date resolves to **one day** (`LAST_N_DAYS:30` = the day 30 days ago; the operator compares with it), unlike SOQL's ranges. On Datetime fields it compares day boundaries in the user's time zone and allows only `greater_than` / `less_than`. `in` covers text, picklist, number and Id fields, and means "includes any of" on multi-select picklists; not dates or checkboxes. Details in `docs/PROGRESS.md`.

- **New operators:** `is_blank`, `is_not_blank`, and `in` / "any of" (one rule, several values, e.g. `Category in Billing;Account`). **Approved 2026-11-15:** adds picklist values to `Operator__c` on `Search_Filter_Rule__mdt` and `Search_Boost_Rule__mdt`. Adding picklist values is a safe upgrade for installed packages; removing them later isn't, so the set is final once released.
- **Relative dates in rule values:** `TODAY`, `YESTERDAY`, `LAST_N_DAYS:n`, `NEXT_N_DAYS:n` for Date and Datetime fields, parsed by a strict allowlist parser (no free text reaches a query). SOQL binds the resolved date; SOSL writes the validated SOQL date literal. Boost rules evaluate against the date resolved at request time.
- **Done when:** the demo config gets a boost "published in the last 30 days +5" and a filter using `in`; table-style tests cover every operator × field type, including invalid combinations (`is_blank` on a checkbox, `LAST_N_DAYS:-1`, `LAST_N_DAYS:abc`, injection attempts in the value).

#### M8.5: Object tabs and results layout (added and approved by the owner 2026-11-20; closed 2026-11-20)

Owner request after M8: let visitors search one object (e.g. only Cases), and make the results page look more like Salesforce's own search. The owner chose the **Experience Cloud search results** look (tabs across the top, stacked result cards, filters in a side panel) over the Lightning Experience global search layout. No data model change.

- **Object scope (Apex):** `SearchRequestDto` gets an optional `objectApiNames` list. Empty means all objects, as today. Names are matched against the validated targets of the active config (unknown or inaccessible names are ignored, like facet selections); only matching objects are queried, so the SOSL row budget goes to them. If nothing matches, the search covers all objects. The response gets `objects[]` (`objectApiName`, `sectionLabel`, `iconName`) listing every object the visitor can search with this config, so tabs show even for objects with no results on this term.
- **Tabs (LWC, `searchResults`):** an **All** tab plus one tab per object, in config sort order, labelled with the section label. SLDS tab pattern with full keyboard support (arrow keys, Home/End) and ARIA `tablist` / `tab` / `tabpanel`; built on `lightning-tabset` if it meets that on LWR, otherwise on the SLDS blueprint (decided in the build, recorded in `docs/PROGRESS.md`). No result counts on tabs: true totals need a count query per object, which is the same cost argument as facet counts (§10.5).
  - **All:** today's grouped view (top results per object). Each group ends with "View all <Section>" (Custom Label), which switches to that object's tab instead of growing every group.
  - **Object tab:** only that object is queried; "Load more" grows only this list. This replaces the shared `limitPerObject` behaviour (backlog item "Load more per object").
  - **Facets:** on an object tab, only that object's facets show. Selections for other objects stay in the URL and apply again on All.
  - **URL:** the tab is written to the page state as `o=<Object API name>` next to `term` and `f`, so back/forward and shared links restore it. Untrusted like `f`: API-name shape check in the component, validated on the server.
- **Layout polish:** closer to the standard Experience Cloud search results: a "Results for "<term>"" heading, tabs under it, filters in a left panel on wide screens (collapsing above the results on narrow ones, as today), result cards with title link, object icon and details on one line. SLDS styling hooks only, no hard-coded colours. A Builder property **Show object tabs** (default on) for sites that want the single grouped list.
- **Tests:** Apex for the scope (unknown and inaccessible objects ignored, minimum-access user, SOSL contains only the scoped objects, row budget recalculated); Jest for tabs (keyboard, ARIA, URL read/write, tampered `o=`, "View all", per-tab Load more, facets per tab) with axe checks; existing tests kept green.
- **Done when:** on the demo site, as Priya, choosing the Cases tab shows only her cases with only the Status filter, "Load more" there doesn't change Help Articles, the tab survives reload and back/forward, a tampered `o=` falls back to All, the tabs work with keyboard only, and the owner agrees the page reads like Salesforce's Experience Cloud search.

#### M9: Agentforce action (v2 headline)

> **Closed 2026-11-20** (owner approved). Changes from the plan below, decided by the owner during the milestone: the spike passed in a **scratch org** (no Developer Edition org); M9 covers a **service agent** only (employee agents and the site channel not verified, stated in the README); the demo agent uses a **separate config**, `Support_Agent_Search` (published **and** guest-visible articles), instead of opting in the site config; results have **no `url`** (a site link needs a site base URL; backlog); the action class is granted by a new permission set, **Site Search Kit Agent**. Details in `docs/PROGRESS.md`.

- **Spike first (go/no-go before any build):** in a scratch org, confirm (a) which scratch org features or edition enable Agentforce; (b) that an `@InvocableMethod` Apex action can be added to an agent topic, and whether the agent's metadata can be deployed from source; (c) **which user the action runs as**, for an employee agent and for a service agent on an Experience site. Record findings in `docs/PROGRESS.md`. If (a) or (b) isn't possible in a scratch org, use a **Developer Edition org** for the agent demo (owner decision, 2026-11-15); Apex tests for the action still run in scratch and packaging orgs.
- **`SiteSearchAction`** (packaged, `with sharing`): `@InvocableMethod` wrapping `SearchService`. Inputs: `configName`, `searchTerm`, optional `maxResults` (default 5, cap 10). Outputs: a short text summary for the agent plus a list of `{ recordId, objectApiName, title, details, url }`. Same user-mode queries, same validation, same Custom Label errors (returned as an output field, not thrown, so the agent can respond).
- **Bulk safety:** invocable methods receive a list of requests, and SOSL is limited per transaction. Process up to a fixed number of requests per call (e.g. 10) and return an error output for the rest; never loop past the SOSL limit. Test with a 200-request list.
- **Agent opt-in (approved 2026-11-15):** new checkbox `Allow_Agent_Access__c` on `Search_Config__mdt` (default off). The action refuses configs that haven't opted in. Reason: a service agent may run as a dedicated agent user whose access differs from the site visitor's, so admins should choose which configs agents may use (typically ones with only public content).
- **Demo (`demo/`, not packaged):** a support agent topic that uses the action with the Support Portal config, if the spike shows it can live in source; otherwise documented manual steps in `docs/SETUP.md`.
- **Docs:** README section "Use with Agentforce" (setup, the running-user caveat, which configs to allow); `docs/SECURITY.md` updated with the agent threat model.
- **Done when:** in the demo org, asking the agent "how do I reset my password?" returns the same top articles as the site search (featured first, no Drafts); a config without `Allow_Agent_Access__c` is refused; tests cover the action as a minimum-access user, the bulk cap, and injection-style terms.

#### M10: Knowledge articles

> **Closed 2026-11-20** (owner approved). **Spike done 2026-11-20 (go).** Data category fields approved (§10.4). Found in the spike: results already link to the article page on LWR and Aura; Apex can't see a guest's site language, so the component sends it (validated on the server); a category filter needs its own SOSL query. Details in `docs/PROGRESS.md`.

- **Spike first:** in a scratch org with Knowledge enabled, confirm SOSL on `Knowledge__kav` (required publish status and language filters, `WITH DATA CATEGORY`), guest access through data category visibility, and the page a result should link to on LWR and Aura. Record findings.
- **Support:** `Knowledge__kav` accepted as `Object__c`. The service adds the "published only" and visitor-language filters itself, not as admin config, so an admin can't expose drafts by mistake. Links go to the article's site page.
- **Data category filter (in scope, owner decision 2026-11-15):** admins can restrict a Knowledge search object to data categories, e.g. "Products › Nimbus Cloud and below". Category group and category names are validated against the data category describe (`Schema.describeDataCategoryGroups` / `describeDataCategoryGroupStructures`) and become a `WITH DATA CATEGORY` clause; nothing unvalidated reaches the query. **⚑ approval of the field design:** the spike proposes the exact fields (e.g. `Data_Category_Group__c` + `Data_Category__c` + operator `AT` / `BELOW` on `Search_Object__mdt`, or a child type for several categories) before they're built.
- **Tests:** Knowledge doesn't exist in every org, so Knowledge-specific tests skip when `Knowledge__kav` isn't in describe, and the packaging scratch definition enables Knowledge. Coverage target stays ≥ 90%.
- **Demo:** a few Knowledge articles next to `Help_Article__c` (created by the setup script, since Knowledge data needs publishing).
- **Done when:** guest and customer searches on the demo site return published Knowledge articles in the visitor's language, never drafts or archived versions, and links open the article page; README has a "Knowledge" setup section.

#### M10.5: Filter panel polish and a new demo object (added and approved by the owner 2026-11-20)

> **Closed 2026-11-20** (owner approved). Built as planned; the demo object also got Summary, Visible to Guests and a New status so the existing stories still work. Details in `docs/PROGRESS.md`.

Owner feedback from the M10 demo check. Planned after M10 closes; no data model change to the packaged Custom Metadata types.

- **Filter panel always in place:** on wide screens the left filter panel shows on every tab, **collapsed by default**, so the layout doesn't jump when a tab's object has no facets (e.g. Knowledge Base). Expanding it on such a tab shows a short note ("No filters for this tab", Custom Label). Narrow screens keep the current behaviour above the results. Keyboard and screen-reader support for the toggle (`aria-expanded`, `aria-controls`).
- **Filter styling:** the panel's headings, spacing and checkboxes match the result cards (SLDS styling hooks only, no hard-coded colours), so the filters read as part of the results page.
- **Demo object `Known_Issue__c` replaces `Help_Article__c`** (demo only, not packaged): Product, Status (Investigating / Fix in progress / Resolved), Severity, Reported Date, Workaround, Featured. Knowledge now covers articles. Sample data, guest sharing, the site config's facets, filters and boosts, the agent config, the site pages and the README move to it.
- **Done when:** on the demo site the panel stays collapsed in place when switching between All, Known Issues, Knowledge Base and Cases; the note shows on tabs without filters; the toggle works with keyboard only (Jest + axe); the owner agrees the panel looks polished; the demo searches Known Issues, Knowledge and Cases, set up from scratch with the README steps.

### 10.4 Data model changes

| Milestone | Change                                                                                                                | Why                                           |
| --------- | --------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| M8        | `Operator__c` (Filter, Boost): add `is_blank`, `is_not_blank`, `in`                                                   | Richer rules                                  |
| M8.5      | None (request/response DTO fields and a component property only)                                                      | Object tabs                                   |
| M9        | `Search_Config__mdt.Allow_Agent_Access__c` (Checkbox, default false)                                                  | Agents only use configs an admin opted in     |
| M10       | `Search_Object__mdt`: `Data_Category_Group__c`, `Data_Category__c`, `Data_Category_Operator__c` (`at`, `at_or_below`) | Restrict Knowledge results to data categories |

M8 and M9 approved 2026-11-15; M10 approved 2026-11-20. M7 needs no data model change.

### 10.5 Staying in the backlog

- **Facet value counts:** one aggregate query per facet per search; costly and easy to get wrong with sharing. Revisit after v2.
- **Prefix / wildcard search:** cheap to build, but it changes result quality for every config, and a per-config toggle would be another field. Revisit with real feedback.

### 10.6 Owner decisions (2026-11-15)

1. **Order:** M7 → M8 → M9 → M10 (low risk first, headline in the middle). **Updated 2026-11-20:** M8.5 (object tabs and results layout) inserted before M9 at the owner's request. M10.5 (filter panel polish, Known Issues demo object) inserted after M10, also at the owner's request.
2. **Agentforce org:** a Developer Edition org is fine for the agent demo if scratch orgs can't run it.
3. **Knowledge scope:** data category filters are in scope (M10).
