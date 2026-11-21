// Demo only: the agent user for Support Search Agent. Safe to run more than once.
// Run through scripts/setup-demo-agent.js, which then publishes and activates the agent.
//
// A service agent runs its actions as this user (verified in the M9 spike), so its access is
// what the agent can search: the Site Search Kit agent action, read access to known issues and
// Knowledge articles, and the Agentforce service agent permission sets. Nothing else.

String lastName = 'Support Agent';
String profileName = 'Einstein Agent User';

List<User> existing = [
  SELECT Id, Username
  FROM User
  WHERE LastName = :lastName AND Profile.Name = :profileName AND IsActive = TRUE
  LIMIT 1
];
User agentUser;
if (existing.isEmpty()) {
  String orgId = UserInfo.getOrganizationId();
  agentUser = new User(
    Username = 'support.agent.' + orgId + '@example.com',
    LastName = lastName,
    FirstName = 'Demo',
    Email = 'support.agent@example.com',
    Alias = 'sagent',
    ProfileId = [SELECT Id FROM Profile WHERE Name = :profileName]
    .Id,
    TimeZoneSidKey = 'America/Los_Angeles',
    LocaleSidKey = 'en_US',
    EmailEncodingKey = 'UTF-8',
    LanguageLocaleKey = 'en_US'
  );
  insert agentUser;
  System.debug('SETUP agent user: created ' + agentUser.Username);
} else {
  agentUser = existing[0];
  System.debug('SETUP agent user: already exists, ' + agentUser.Username);
}

Set<String> wanted = new Set<String>{
  'Site_Search_Kit_Agent',
  'Support_Demo_Agent',
  'AgentforceServiceAgentBase',
  'AgentforceServiceAgentUser'
};
Set<Id> assigned = new Set<Id>();
for (PermissionSetAssignment psa : [
  SELECT PermissionSetId
  FROM PermissionSetAssignment
  WHERE AssigneeId = :agentUser.Id
]) {
  assigned.add(psa.PermissionSetId);
}
List<PermissionSetAssignment> toAssign = new List<PermissionSetAssignment>();
for (PermissionSet ps : [
  SELECT Id, Name
  FROM PermissionSet
  WHERE Name IN :wanted AND IsOwnedByProfile = FALSE
]) {
  if (!assigned.contains(ps.Id)) {
    toAssign.add(
      new PermissionSetAssignment(
        AssigneeId = agentUser.Id,
        PermissionSetId = ps.Id
      )
    );
  }
}
insert toAssign;
System.debug(
  'SETUP agent permission sets: ' + toAssign.size() + ' new assignment(s)'
);

// The Node wrapper writes this username into the agent before publishing it.
System.debug('SETUP_AGENT_USER ' + agentUser.Username);
