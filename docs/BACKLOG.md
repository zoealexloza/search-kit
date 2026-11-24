# Backlog

Ideas that are out of scope for the current milestone. Not commitments. Items that became part of the approved v2 plan are listed at the end with their milestone; their details live in `docs/SPEC.md` §10.

| Idea                                         | Notes                                                                                                                                                                                                                                                                                      | Added      |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- |
| Prefix / wildcard search                     | Visitors can't use `*` or `?` today, because reserved characters are stripped. Could append a trailing `*` to the last word when it has 3+ characters. Kept out of v2 (SPEC §10.5).                                                                                                        | 2026-11-13 |
| Facet value counts                           | Show a count for each facet value. Counting only the returned page would be misleading; real counts need an aggregate SOQL query per facet, which costs queries. Kept out of v2 (SPEC §10.5).                                                                                              | 2026-11-13 |
| Relative dates as ranges                     | `equals TODAY` on a Datetime field would need two conditions (start and end of day), so M8 rejects it; `greater_than` / `less_than` cover most needs. Could add a range operator later.                                                                                                    | 2026-11-20 |
| Site link in agent results                   | `SiteSearchAction` results have no URL: Apex in an agent can only build the internal Lightning record URL. A link to the site's record page would need the site's base URL, e.g. a field on `Search_Config__mdt` (data model change).                                                      | 2026-11-20 |
| Verify employee agents and the site channel  | M9 tested a service agent through `sf agent preview`. Still open: which user an employee agent's action runs as (needs Agentforce Builder; the CLI's Agent Script tooling builds service-style agents), and an agent embedded on the Experience Cloud site (Messaging for In-App and Web). | 2026-11-20 |
| `not_in` operator                            | M8 has `in` but no negation. Adding a picklist value later is a safe package upgrade. Values that contain `;` can't be listed in `in` either.                                                                                                                                              | 2026-11-20 |
| Several data categories per Knowledge object | M10 allows one category (group, category, at or at or below) per search object. Several categories or groups would need a child type; adding a new type later is a safe package upgrade.                                                                                                   | 2026-11-20 |
| Facet values per record type                 | Status values that depend on record type. Apex describe has no per-record-type picklist values (only the UI API, via a callout guests can't make). The facet Values list covers most cases.                                                                                                | 2026-11-24 |
| Longer facet Values lists                    | `Values__c` is Text (255) because `getAll()` cuts long text area values at 255 characters and visitors can't query the config types. A child type with one record per value would remove the limit and allow per-value labels (data model change).                                         | 2026-11-24 |

## Moved into the v2 plan

| Idea                          | Milestone |
| ----------------------------- | --------- |
| More operators                | M8        |
| Load more per object          | M8.5      |
| Search one object (tabs)      | M8.5      |
| Relative dates in rule values | M8        |
| Agentforce action             | M9 (done) |
| Knowledge article support     | M10       |
