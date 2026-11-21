# Setup notes

Notes on the demo site build steps, and why some settings aren't in source control.

## Activate the demo site

`sf community create` and `sf community publish` leave the "Support Portal" site in **Under Construction** status, which guests can't reach. README step 10 activates it through the API:

```bash
sf data update record -s Network -w "Name='Support Portal'" -v "Status=Live"
```

To confirm, run `sf data query -q "SELECT Name, Status FROM Network"`. Status should be `Live`. In Setup, the same switch is **Digital Experiences → All Sites → Workspaces → Administration → Settings → Activate**.

**Why not in source control:** activation also lives in the site's `Network` metadata, but the retrieved `Network` and `CustomSite` files contain org-specific personal data: the email address of the user who created the site (email sender) and that user's username (site admin and guest record owner). Committing them would leak it into a public repo and fail to deploy to other orgs. Updating fields on the `Network` record avoids both (tested 2026-11-14 on a fresh scratch org). `scripts/setup-demo-users.js` sets another `Network` field the same way: `OptionsGuestChatterEnabled`, which is "Allow guest users to access public APIs".

## Site pages in source control

The site's pages live in `demo/main/default/digitalExperiences/` (a `DigitalExperienceBundle`) and `digitalExperienceConfigs/`. They hold no personal data. Rules for changing them:

1. **Create the site before deploying.** The bundle updates the site that `sf community create` makes; it can't create one. The first deploy needs `--ignore-conflicts`, because the new site's template pages count as org changes.
2. **Edit pages in Experience Builder, then retrieve:**
   `sf project retrieve start -m "DigitalExperienceBundle:site/Support_Portal1" --ignore-conflicts`
3. **Strip `contentKey` from every `_meta.json` before committing.** The keys differ in every org. Without them the platform matches items by `apiName` (tested: no duplicates, existing keys kept), so the bundle deploys to any org:
   `find demo/main/default/digitalExperiences -name _meta.json -exec perl -0pi -e 's/,\n  "contentKey" : "[A-Z0-9]+"//' {} \;`
4. **Never commit `Network` or `CustomSite`** (personal data, see above).

Prettier skips these files (`.prettierignore`), so retrieves diff cleanly. Custom-object pages are keyed by API name (`detail-Known_Issue__c`), not the org-specific key prefix, so they are portable too.

## Notes on the scratch org definition

- `features: ["Communities"]` plus `communitiesSettings.enableNetworksEnabled` and `experienceBundleSettings.enableExperienceBundleMetadata` are enough to create LWR sites. Verified 2026-11-13 on API 68.0.
- For the LWR template, `sf community create` accepts `AuthenticationType` values of `AUTHENTICATED` or `AUTHENTICATED_WITH_PUBLIC_ACCESS_ENABLED`. The CLI help example that uses `UNAUTHENTICATED` fails with "AuthenticationType 'UNAUTHENTICATED' is not supported for LWR sites."
