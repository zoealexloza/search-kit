// Demo only: moves the reported date of three known issues to a few days ago, so the demo boost
// "reported in the last 30 days" always has recent issues to promote (the sample data has
// fixed dates). Safe to run more than once. Run through scripts/setup-demo-users.js.
//
// Separate from setup-demo-users.apex because Apex can't change setup objects (users,
// permission set assignments) and regular records in one transaction (MIXED_DML_OPERATION).

Map<String, Integer> daysAgoByIssue = new Map<String, Integer>{
  'Password reset emails delayed for Outlook.com addresses' => 3,
  'Offline edits lost when the app is closed during sync' => 10,
  'Dashboard charts blank after the April release' => 20
};
List<Known_Issue__c> recent = [
  SELECT Id, Name
  FROM Known_Issue__c
  WHERE Name IN :daysAgoByIssue.keySet()
];
for (Known_Issue__c issue : recent) {
  issue.Reported_Date__c = Date.today().addDays(-daysAgoByIssue.get(issue.Name));
}
update recent;
System.debug(
  'SETUP recent issues: ' +
    recent.size() +
    ' reported date(s) moved into the last 30 days'
);
