# Security

How Search Kit protects data, what it asks admins to configure, and what static analysis reports. Written for reviewers and admins evaluating the package.

## Security model

Search Kit never decides who can see what. The platform does: every query runs as the visitor, so their object permissions, field-level security and record sharing apply. The search configuration only narrows results further.

| Layer            | How it's enforced                                                                                                                                                                                                                                                                                         |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Sharing**      | Every class that queries data is `with sharing`. Helpers are `inherited sharing`, with the reason in their header. No `without sharing` anywhere.                                                                                                                                                         |
| **CRUD / FLS**   | Every SOSL and SOQL query runs in **user mode**: `Search.query(q, AccessLevel.USER_MODE)` and `Database.queryWithBinds(q, binds, AccessLevel.USER_MODE)`. Before a query is built, `SchemaValidator` also skips objects and fields the user can't read, so an inaccessible field never reaches the query. |
| **Entry points** | Two, each granted by its own permission set: `SiteSearchController.search` (`@AuraEnabled`, **Site Search Kit User**) for site visitors, and `SiteSearchAction.search` (`@InvocableMethod`, **Site Search Kit Agent**) for Agentforce agents. Everything else is reachable only through them.             |
| **Errors**       | The controller returns Custom Label messages only. Unexpected exceptions are logged and replaced with a generic message, so no stack traces or field names reach the browser.                                                                                                                             |
| **Rendering**    | LWCs render record data as text through template bindings. No `innerHTML`, no `lwc:dom="manual"`. Rich text is stripped to plain text server-side.                                                                                                                                                        |

### Query construction

Search configuration comes from Custom Metadata, and the request comes from the browser. Neither is trusted. Nothing is concatenated into a query until it has been validated:

- **Object and field names** must match an API-name pattern, exist in the `Schema` describe for the running user, and be referenced by the active configuration. The query uses the describe result's name, never the configured text (`SearchTarget`).
- **Lookup detail fields** (since 2026-11-24) are selected as `<relationship>.<name field>`, e.g. `Account.Name`. Config still holds only the lookup's API name; both parts of the path come from describe results (`getRelationshipName()`, and the related object's `isNameField()` field, or `Name` for polymorphic lookups). Every object the lookup can point to, and its name field, must be readable by the running user, or the detail is skipped: a user-mode query naming an unreadable relationship fails as a whole (verified in a scratch org).
- **The search term** has SOSL reserved characters, quotes, backslashes and control characters replaced with spaces. It's capped at 100 characters, and raw input is cut to 1,000 first. Wildcards and boolean syntax aren't available to visitors.
- **Filter, boost and facet values** are converted to typed values first: active picklist values in their canonical spelling, Integer/Long/Decimal, Date, Datetime or Boolean. SOQL binds every value. SOSL can't bind a variable number of values, so SOSL writes the already-typed values as literals, escaping backslashes and then quotes.
  - An `in` rule's value is split on `;` and **every** part is converted the same way; one invalid part rejects the whole rule (and, for a filter, skips the object).
  - **Relative dates** (`TODAY`, `YESTERDAY`, `LAST_N_DAYS:n`, `NEXT_N_DAYS:n`) are parsed by `RelativeDateParser`, a strict allowlist: the whole value must match one of four forms with n of at most four digits. It returns a `Date`, so only a resolved date (bound in SOQL, a formatted date literal in SOSL) reaches a query, never the configured text.
  - `is_blank` / `is_not_blank` take no value and are written as the constant `= null` / `!= null`.
- **Facet selections from the browser** are accepted only for facets in the active configuration, and only with values that are valid for the field. Anything else is ignored. The number of selections and values per request is capped. Since M8 that includes values a filter rule on the same field rules out (the facet doesn't offer them either), so a selection can never undo or bypass a filter. Since M7 selections can also come from the page URL (`?f=`, so filtered results can be shared); the component parses that parameter with its own size caps and API-name checks, and the server validates it like any other request, so an edited URL can only select values the visitor could have clicked. Since M8.5 the URL can also name an object tab (`?o=`): the component accepts only an API-name shape, and the server matches it against the objects that already passed validation for the visitor, so it can narrow a search but never add an object; an unknown name searches every object.
- **Knowledge (since M10):** the data category group and category names reach a query only as the names returned by the running user's data category describe (`KnowledgeSupport`), with the constant operator `AT` or `BELOW`. The visitor's language comes from the browser, so it's untrusted: it is used only if it matches an active value of the article object's `Language` picklist describe, and then written in that canonical spelling.
- **No raw WHERE clauses** in configuration. Filters are structured rules: field, operator, value.

### Failing closed

- An **invalid filter rule** (typo, deleted field, wrong value type) skips its whole object. A mistake can't silently drop a filter such as `Status = Published` and expose Draft records.
- An invalid object or title field skips the object. An invalid detail field, boost rule or facet skips only that entry. Every skip is logged at WARN, so admins can see why something is missing.
- A **Knowledge object** whose configured data category is invalid or not visible to the running user is skipped, rather than searched without the restriction. So are article objects whose `PublishStatus` or `Language` field the user can't read, since the published-only filter depends on them.
- An object the running user can't even describe (Knowledge without access throws `NoAccessException`) is skipped like an unknown object, so it can't fail the whole search.
- Unknown or inactive configurations are rejected.

## Guest users (Experience Cloud)

Guests are the highest-risk audience. The package grants nothing to guests by itself. The README's [Guest user setup](../README.md#guest-user-setup) lists exactly what an admin grants, and the demo follows it:

- **Record access comes from sharing rules, not the search config.** Guests' org-wide default is always Private. The demo shares only known issues that are confirmed (status not New) **and** opted in with a `Visible to Guests` checkbox, so new issues are hidden from guests by default. Search filters only decide what appears in results.
- **Object access is opt-in per object.** An object without Read is skipped. The demo guest can't read Case at all.
- **"Allow guest users to access public APIs"** is needed only for standard Lightning record pages (UI API), not for the search. It lets anyone call the API for records the guest can read, and it was abused in 2026's guest-data scraping campaigns. The README says to turn it on only when the guest can read nothing you wouldn't publish. The guest profile does **not** need **API Enabled**; it was tested and isn't required.
- **Search is limited by design.** No wildcards and no "return everything" query: with no term and no facet selected, nothing is queried. Results per object are capped (config maximum 50; "Load more" maximum 200).

### Logged-in external users

Customer Community users can't be added to sharing rules. The demo uses an external default of Read for known issues, with the search's confirmed-only filter. An unconfirmed (New) issue is therefore reachable by direct link unless the admin adds a restriction rule in Setup; the README documents this as optional hardening. Cases are shared by account through a sharing set, so a customer sees only their own account's cases.

## Knowledge articles

Since M10 an article object (`__kav`) can be a search object. The service adds `PublishStatus = 'Online'` and the language itself, for every audience; they aren't configuration, so a mistake can't expose drafts. Tested in a spike: SOQL on articles has no implicit filter (an internal user gets drafts, archived versions and every language), and a language value that isn't active throws. For guests and customers, Salesforce itself already limits articles to the published versions in their channel and visible data categories (tested, including a draft with the guest channel flag set); the service's filters are a second layer and the only one for internal users. Packaged code refers to Knowledge only by name, so Knowledge is not a package dependency.

## Agentforce agents

`SiteSearchAction` (since M9) lets an agent search with a configuration. The threat model differs from the site in one way: **who the query runs as.**

- **A service agent runs its actions as its agent user**, a dedicated user on the Einstein Agent licence, not as the person chatting. Tested in a scratch org: the action's Apex ran as the agent user. The search therefore sees what the agent user can read, and the agent can repeat it to anyone. User mode and `with sharing` still apply, but to the agent user.
- **Configs are opt-in.** The action refuses any config without `Allow_Agent_Access__c` (default off) and returns a Custom Label message instead. A site config never becomes available to agents by accident. The README tells admins to opt in only configs with content they'd publish.
- **Least privilege for the agent user.** **Site Search Kit Agent** grants the action class only; object and field Read are granted separately, as for guests. The demo's agent user gets known issues and Knowledge only, and its config adds `Visible to Guests = true` to the confirmed-only filter, so the agent can't surface the customer-only issues that guests can't see (internal sharing for known issues is Read, so sharing alone wouldn't stop it).
- **Same validation as the site.** The action builds a `SearchRequestDto` and calls `SearchService`: config allowlists, term sanitizing and fail-closed filters are shared code. The term comes from the language model, so it's treated exactly like browser input. The demo agent fixes the config name as a constant in its Agent Script, so the model can't choose another config; even if it could, only opted-in configs work.
- **Errors don't leak.** Expected errors return their Custom Label message; unexpected ones are logged and replaced with the generic label (tested with a stub that throws a query error).
- **Bulk limits.** At most 10 requests are searched per call, and only while at least two SOSL queries are left in the transaction (a search uses one, plus one for a Knowledge object with a data category); the rest get an error response. `SearchService` also stops before the SOSL limit, whose exception can't be caught. Tested with 200 requests and with a transaction that has already used all but two queries.
- **Knowledge for agents:** the agent user sees the internal channel, so the demo's agent config adds `IsVisibleInPkb = true` to its Knowledge object, and restricts it to a data category (tested: the agent didn't reveal an internal-only article it was asked about).
- **Not verified:** which user an _employee_ agent's action runs as (the CLI's source tooling only builds service-style agents), and an agent embedded on an Experience Cloud site. Both stay within the two safeguards above: the opt-in decides which configs, and the running user's own access decides what's found.

## Tests

138 Apex tests, 97% org-wide coverage (every search class 99–100%, `SiteSearchAction` 100%). Security-relevant cases include:

- Objects and fields hidden from the user: `System.runAs` a Minimum Access user, with and without Account Read.
- Injection-style input: `'`, `\`, `\'`, SOSL reserved characters, `RETURNING` / `}` break-out attempts, and a 100,000-character term. Since M8 also in rule values: `in` lists with an injected part, and relative dates with trailing text (`LAST_N_DAYS:30 OR Id != null`, `TODAY' OR …`), negative or non-numeric n.
- Invalid configuration: unknown fields, wrong value types, unsupported operators (operator × field type tables), and filter rules that must fail closed.
- Filter and boost agree: each new operator runs as a real SOQL filter and through the boost engine on the same records, with the same result.
- Facet selections for unconfigured fields or invalid values.
- Agent action: configs without agent access are refused, unknown configs and unexpected errors return label messages only, a minimum-access user gets no records, injection-style terms return only configured objects, and 200 requests run at most 10 SOSL queries.
- Every SOSL path uses `Test.setFixedSearchResults`.

140 LWC Jest tests, including axe-core accessibility checks.

Guest and logged-in customer access was tested end to end in scratch orgs, as an anonymous visitor through the site's API and with record-access checks per user. Details are in `docs/PROGRESS.md` (Milestone 5).

## Static analysis

Salesforce Code Analyzer (`sf code-analyzer run --workspace force-app --workspace demo --workspace scripts`, with PMD on Java 21), last run 2026-11-20 (M9):

**0 security findings.** No sharing, SOQL/SOSL injection, CRUD/FLS or XSS violations. 219 non-security findings, all reviewed:

| Area           | Rule                                                                | Count | Decision                                                                                                                                                                                                                                                              |
| -------------- | ------------------------------------------------------------------- | ----: | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Packaged code  | `CyclomaticComplexity`, `CognitiveComplexity`                       |    15 | Accepted. The large methods were split in M2. The rest are the operator/type matrices (`SchemaValidator.parseRuleValue` / `parseTypedValue`, `BoostRuleEngine.compareValues`), which read best as one flat branch per type, plus class totals with no method above 9. |
| Packaged code  | `ExcessiveParameterList`, `AvoidBooleanMethodParameters`            |     6 | Accepted. Mostly the scoring method, whose parameters are the formula's inputs.                                                                                                                                                                                       |
| Packaged code  | `AvoidDebugStatements`                                              |     4 | Intentional. The WARN logs tell admins why a configured field was skipped; the ERROR logs in the controller and the agent action keep internal details out of responses.                                                                                              |
| Packaged code  | `AvoidGlobalModifier`                                               |     1 | Intentional. `SearchConfigPicklist` (`VisualEditor.DynamicPickList`) follows the documented pattern so Experience Builder can reach it from a namespaced package later.                                                                                               |
| Packaged code  | `no-hardcoded-values-slds2`                                         |     5 | Accepted. `100%` widths; no SLDS styling hook exists for a percentage.                                                                                                                                                                                                |
| Tests          | `ApexUnitTestClassShouldHaveRunAs`                                  |   122 | Accepted. Pure-logic tests gain nothing from `runAs`; the access tests use it.                                                                                                                                                                                        |
| Tests          | `ApexDoc`, `ExcessiveParameterList`, `AvoidBooleanMethodParameters` |    43 | Accepted. Test factories and test methods. Production classes are fully documented.                                                                                                                                                                                   |
| Tests          | ESLint `no-async-operation`, `no-unexpected-wire-adapter-usages`    |     7 | Accepted. Code Analyzer doesn't apply the project's `eslint.config.js`, which turns these off for tests.                                                                                                                                                              |
| Tests          | `OperationWithLimitsInLoop`, `CyclomaticComplexity`                 |     4 | Accepted. `SearchQueryBuilderTest` runs each M8 operator as a real query and through the boost engine (two queries for each of 10 cases, by design); the class totals (`SearchQueryBuilderTest`, `SearchServiceTest`) are the sum of small tests.                     |
| Demo / scripts | ESLint rules on demo LWC tests, site template CSS and Node scripts  |    12 | Not packaged. LWC-only rules (`no-process-env`) applied to Node scripts, and the site template's own CSS.                                                                                                                                                             |

Earlier milestones fixed every finding that wasn't accepted (eager describes, copy-paste blocks, hard-coded CSS values, missing ApexDoc). See `docs/PROGRESS.md`.

## Reporting a vulnerability

Please open a private security advisory on the GitHub repository rather than a public issue.
