// Generates data/*.json for `sf data import tree`. Usage: node scripts/generate-sample-data.js <repoRoot>
const fs = require("fs");
const path = require("path");
const out = path.join(process.argv[2], "data");
fs.mkdirSync(out, { recursive: true });

const N = "Nimbus Cloud",
  A = "Atlas Mobile",
  B = "Beacon Analytics";
const NEW = "New",
  INV = "Investigating",
  FIX = "Fix in Progress",
  RES = "Resolved";
const GUESTS = true,
  CUSTOMERS = false;

// [title, summary, workaround, products[], status, severity, featured, reportedDate, guests]
// guests: Visible_to_Guests__c. Guests see an issue only if it is also confirmed (not New),
// through the guest sharing rule; logged-in customers see every issue the search shows.
const issues = [
  // --- "password" demo cluster: 4 for guests (featured first), 1 unconfirmed ---
  [
    "Password reset emails delayed for Outlook.com addresses",
    "Password reset emails to Outlook.com and Hotmail addresses can take up to an hour to arrive.",
    "Add noreply@nimbus.example to your safe senders, or ask your admin to send the reset link from the admin console.",
    [N],
    INV,
    "High",
    true,
    "2026-04-02",
    GUESTS
  ],
  [
    "Two-factor codes rejected after changing the phone's time zone",
    "After the password, authenticator codes are rejected at login when the phone's clock or time zone was changed manually.",
    "Turn on automatic date and time on the phone, then sign in again.",
    [N, A],
    FIX,
    "Medium",
    false,
    "2026-03-15",
    GUESTS
  ],
  [
    "Login loop on Safari when cross-site tracking is blocked",
    "Safari users with Prevent Cross-Site Tracking on were sent back to the login page after entering their password.",
    "Fixed in the March release. Clear the browser cache if it still happens.",
    [N],
    RES,
    "Medium",
    false,
    "2026-01-22",
    GUESTS
  ],
  [
    "New password not accepted by Atlas Mobile until the next sign-in",
    "After a password change, Atlas Mobile keeps asking for the old password until you sign out and in again.",
    "Sign out of Atlas Mobile and sign in with the new password.",
    [A],
    INV,
    "Low",
    false,
    "2026-04-18",
    GUESTS
  ],
  [
    "Locked out after five failed password attempts on SSO accounts",
    "Reported: SSO users are locked out by password attempts they never made. Not confirmed yet.",
    "",
    [N],
    NEW,
    "High",
    false,
    "2026-04-20",
    GUESTS
  ],
  // --- "invoice" demo cluster: guests see 2, logged-in customers see 4 ---
  [
    "Invoice PDF shows the old company address",
    "Invoices generated after an address change still show the previous address on the PDF.",
    "Download the invoice again after 24 hours; the PDF is regenerated overnight.",
    [N],
    FIX,
    "Medium",
    false,
    "2026-03-28",
    CUSTOMERS
  ],
  [
    "Duplicate invoice emails for annual plans",
    "Customers on annual plans received the renewal invoice email twice.",
    "Fixed. Only one invoice was charged; the second email can be ignored.",
    [N],
    RES,
    "Low",
    false,
    "2026-02-10",
    CUSTOMERS
  ],
  [
    "Invoice totals rounded differently in the CSV export",
    "Totals in the invoice CSV export can differ by one cent from the PDF because of rounding.",
    "Use the PDF amount for accounting; the export will match after the fix.",
    [B],
    INV,
    "Low",
    false,
    "2026-03-05",
    GUESTS
  ],
  [
    "Invoice download times out for accounts with many invoices",
    "The invoice list fails to load for accounts with more than 500 invoices.",
    "Filter the list by year before downloading.",
    [N],
    FIX,
    "Medium",
    false,
    "2026-02-25",
    GUESTS
  ],
  [
    "Tax missing on invoices for new EU customers",
    "Reported: VAT is missing on the first invoice of some new EU accounts. Not confirmed yet.",
    "",
    [N],
    NEW,
    "High",
    false,
    "2026-04-19",
    GUESTS
  ],
  // --- sync and mobile ---
  [
    "Offline edits lost when the app is closed during sync",
    "Changes made offline can be lost if Atlas Mobile is closed while it is syncing them.",
    "Keep the app open until the sync icon disappears. Version 5.3 fixes this.",
    [A],
    FIX,
    "Critical",
    true,
    "2026-04-05",
    GUESTS
  ],
  [
    "Photos attached offline upload twice",
    "Photos added to a record while offline were uploaded twice after reconnecting.",
    "Fixed in 5.2. Delete the duplicate photo from the record.",
    [A],
    RES,
    "Low",
    false,
    "2026-01-30",
    GUESTS
  ],
  [
    "Sync stalls at 99% on Android 15",
    "On some Android 15 devices the first sync after an update never finishes.",
    "Restart the app, or turn off battery optimization for Atlas Mobile.",
    [A],
    INV,
    "High",
    false,
    "2026-04-12",
    GUESTS
  ],
  [
    "Battery drain from background sync on iOS",
    "Background sync used more battery than expected on iOS 19.",
    "Fixed in 5.1.",
    [A],
    RES,
    "Medium",
    false,
    "2026-01-08",
    GUESTS
  ],
  [
    "Calendar sync duplicates recurring events",
    "Recurring events edited on the phone appear twice in the web calendar.",
    "Edit recurring events in the web app until the fix ships.",
    [A, N],
    FIX,
    "Medium",
    false,
    "2026-03-20",
    GUESTS
  ],
  // --- dashboards and reports ---
  [
    "Dashboard charts blank after the April release",
    "Some dashboards show empty charts since the April release when a filter uses a date range.",
    "Remove and re-add the date filter, or use a relative range such as Last 30 days.",
    [B],
    FIX,
    "High",
    true,
    "2026-04-08",
    GUESTS
  ],
  [
    "Scheduled report emails an hour late after the clock change",
    "Scheduled reports were sent an hour late after daylight saving time started.",
    "Fixed. Schedules use your time zone again.",
    [B],
    RES,
    "Low",
    false,
    "2026-03-31",
    GUESTS
  ],
  [
    "Map chart shows the wrong region for some postcodes",
    "A few postcodes are placed in a neighbouring region on map charts.",
    "Group by city instead of postcode for now.",
    [B],
    INV,
    "Low",
    false,
    "2026-02-14",
    GUESTS
  ],
  [
    "CSV export drops leading zeros",
    "Values such as 00123 lose their leading zeros when a report is exported to CSV.",
    "Export to Excel instead, which keeps the values as text.",
    [B],
    INV,
    "Medium",
    false,
    "2026-03-11",
    GUESTS
  ],
  [
    "Dashboard filters reset when sharing a link",
    "Reported: filters are lost when a dashboard link is opened by another user. Not confirmed yet.",
    "",
    [B],
    NEW,
    "Medium",
    false,
    "2026-04-21",
    GUESTS
  ],
  [
    "Data import rejects UTF-8 files with a byte order mark",
    "CSV files saved with a byte order mark (BOM) failed to import.",
    "Fixed. Files with or without a BOM import correctly.",
    [B],
    RES,
    "Low",
    false,
    "2026-01-15",
    GUESTS
  ],
  // --- Nimbus Cloud ---
  [
    "File uploads over 2 GB fail",
    "Uploading a single file larger than 2 GB stops at 99%.",
    "Split the file, or use the desktop sync client, which isn't affected.",
    [N],
    INV,
    "Medium",
    false,
    "2026-03-02",
    GUESTS
  ],
  [
    "Search misses files renamed today",
    "Files renamed in the last few hours were not found by their new name.",
    "Fixed. The search index updates within minutes again.",
    [N],
    RES,
    "Low",
    false,
    "2026-02-03",
    GUESTS
  ],
  [
    "New subfolders don't inherit shared folder permissions",
    "Subfolders created inside a shared folder are private to their creator.",
    "Share the subfolder again from the folder's Share menu.",
    [N],
    FIX,
    "High",
    false,
    "2026-03-25",
    GUESTS
  ],
  [
    "API rate limit errors during nightly backups",
    "Backup tools hit API rate limits on large accounts between 1 and 3 AM UTC.",
    "Spread backups over the night, or ask support for a temporary limit increase.",
    [N, B],
    INV,
    "Medium",
    false,
    "2026-03-18",
    CUSTOMERS
  ],
  [
    "Notification emails show raw HTML in some email apps",
    "Some email apps showed the HTML code of notification emails instead of the message.",
    "Fixed. Notifications include a plain-text version.",
    [N, A, B],
    RES,
    "Low",
    false,
    "2026-01-12",
    GUESTS
  ],
  [
    "Admin console slow for large teams",
    "The users page in the admin console takes up to 30 seconds to load for teams over 2,000 users.",
    "Search for a user by name instead of scrolling the full list.",
    [N],
    INV,
    "Medium",
    false,
    "2026-04-01",
    GUESTS
  ],
  [
    "Workspace invite links expire too early",
    "Reported: invite links stop working after a few hours instead of 7 days. Not confirmed yet.",
    "",
    [N],
    NEW,
    "Medium",
    false,
    "2026-04-22",
    GUESTS
  ]
];

const records = issues.map((issue, i) => {
  const r = {
    attributes: { type: "Known_Issue__c", referenceId: `IssueRef${i + 1}` },
    Name: issue[0],
    Summary__c: issue[1],
    Product__c: issue[3].join(";"),
    Status__c: issue[4],
    Severity__c: issue[5],
    Featured__c: issue[6],
    Reported_Date__c: issue[7],
    Visible_to_Guests__c: issue[8]
  };
  if (issue[2]) r.Workaround__c = issue[2];
  return r;
});

const accounts = [
  ["Brightwater Logistics", "AccountRef1"],
  ["Juniper Lane Bakery", "AccountRef2"],
  ["Northfield Dental Group", "AccountRef3"]
].map(([Name, referenceId]) => ({
  attributes: { type: "Account", referenceId },
  Name
}));

const contacts = [
  ["Priya", "Raman", "AccountRef1"],
  ["Marcus", "Okafor", "AccountRef1"],
  ["Elena", "Petrova", "AccountRef2"],
  ["Sam", "Whitfield", "AccountRef3"]
].map(([FirstName, LastName, acc], i) => ({
  attributes: { type: "Contact", referenceId: `ContactRef${i + 1}` },
  FirstName,
  LastName,
  Email: `${FirstName.toLowerCase()}.${LastName.toLowerCase()}@example.com`,
  AccountId: `@${acc}`
}));

// [subject, description, status, priority, contactIdx(1-based), accountRef]
const cases = [
  [
    "Cannot reset password",
    "The password reset email never arrives for two of our users.",
    "New",
    "High",
    1,
    "AccountRef1"
  ],
  [
    "Invoice has the wrong address",
    "Our March invoice shows our old warehouse address.",
    "Working",
    "Medium",
    2,
    "AccountRef1"
  ],
  [
    "Mobile app sync stuck",
    "Atlas Mobile has not synced since yesterday. Offline changes are piling up.",
    "Escalated",
    "High",
    1,
    "AccountRef1"
  ],
  [
    "Need a copy of last year invoices",
    "Please send all invoices for 2025 for our accountant.",
    "Closed",
    "Low",
    3,
    "AccountRef2"
  ],
  [
    "Export to CSV times out",
    "Exporting the sales dashboard to CSV fails after a few minutes.",
    "New",
    "Medium",
    3,
    "AccountRef2"
  ],
  [
    "Locked out after password change",
    "After changing my password I am locked out of the mobile app.",
    "Working",
    "High",
    4,
    "AccountRef3"
  ],
  [
    "Add a billing contact",
    "Please add our office manager as a billing contact.",
    "Closed",
    "Low",
    4,
    "AccountRef3"
  ],
  [
    "Dashboard shows no data for May",
    "All charts are empty when I pick May.",
    "Closed",
    "Medium",
    2,
    "AccountRef1"
  ],
  [
    "Question about plan upgrade",
    "What changes if we upgrade to the annual plan?",
    "Closed",
    "Low",
    3,
    "AccountRef2"
  ]
].map(([Subject, Description, Status, Priority, c, acc], i) => ({
  attributes: { type: "Case", referenceId: `CaseRef${i + 1}` },
  Subject,
  Description,
  Status,
  Priority,
  Origin: "Web",
  ContactId: `@ContactRef${c}`,
  AccountId: `@${acc}`
}));

const write = (file, recs) =>
  fs.writeFileSync(
    path.join(out, file),
    JSON.stringify({ records: recs }, null, 2) + "\n"
  );
write("Known_Issue__c.json", records);
write("Account.json", accounts);
write("Contact.json", contacts);
write("Case.json", cases);

const plan = [
  {
    sobject: "Known_Issue__c",
    saveRefs: false,
    resolveRefs: false,
    files: ["Known_Issue__c.json"]
  },
  {
    sobject: "Account",
    saveRefs: true,
    resolveRefs: false,
    files: ["Account.json"]
  },
  {
    sobject: "Contact",
    saveRefs: true,
    resolveRefs: true,
    files: ["Contact.json"]
  },
  { sobject: "Case", saveRefs: false, resolveRefs: true, files: ["Case.json"] }
];
fs.writeFileSync(
  path.join(out, "sample-data-plan.json"),
  JSON.stringify(plan, null, 2) + "\n"
);
console.log(
  `issues=${records.length} accounts=${accounts.length} contacts=${contacts.length} cases=${cases.length} total=${records.length + accounts.length + contacts.length + cases.length}`
);
