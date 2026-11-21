// Demo only: sets up who can use the Support Portal demo site. Safe to run more than once.
// Run through scripts/setup-demo-users.js, which also adds the customer profile to the site's
// members (NetworkMemberGroup can be created through the API but not with Apex DML).
//
// 1. Gives the running user (owner of the demo accounts) the Support_Portal_Owner role.
//    Customer users can only be created for accounts whose owner has a role.
// 2. Gives the site guest user Site_Search_Kit_User (Apex class) and Support_Demo_Guest
//    (Known_Issue__c and Knowledge read). Which issues a guest sees is set by the guest sharing rule.
// 3. Creates a Customer Community user for the demo contact Priya Raman, with
//    Site_Search_Kit_User and Support_Demo_User. The sharing set gives her her account's cases.

String siteName = 'Support Portal';
String guestProfile = 'Support Portal Profile';
String customerProfile = 'Support_Portal_Customer';
String customerEmail = 'priya.raman@example.com';

// 1. Role for the account owner
User me = [SELECT Id, UserRoleId FROM User WHERE Id = :UserInfo.getUserId()];
if (me.UserRoleId == null) {
  me.UserRoleId = [
    SELECT Id
    FROM UserRole
    WHERE DeveloperName = 'Support_Portal_Owner'
  ]
  .Id;
  update me;
  System.debug('SETUP role: Support_Portal_Owner given to the running user');
} else {
  System.debug('SETUP role: running user already has a role');
}

// 1b. Knowledge User for the running user, needed to create the demo Knowledge articles
//     (setup-demo-knowledge.apex, a separate transaction).
User knowledgeAuthor = [
  SELECT Id, UserPermissionsKnowledgeUser
  FROM User
  WHERE Id = :UserInfo.getUserId()
];
if (!knowledgeAuthor.UserPermissionsKnowledgeUser) {
  knowledgeAuthor.UserPermissionsKnowledgeUser = true;
  update knowledgeAuthor;
  System.debug('SETUP knowledge: running user is now a Knowledge user');
} else {
  System.debug('SETUP knowledge: running user is already a Knowledge user');
}

Map<String, Id> permSets = new Map<String, Id>();
for (PermissionSet ps : [
  SELECT Id, Name
  FROM PermissionSet
  WHERE
    Name IN ('Site_Search_Kit_User', 'Support_Demo_Guest', 'Support_Demo_User')
]) {
  permSets.put(ps.Name, ps.Id);
}

// 2. Guest user
List<User> guests = [
  SELECT Id
  FROM User
  WHERE UserType = 'Guest' AND Profile.Name = :guestProfile AND IsActive = TRUE
];
if (guests.isEmpty()) {
  throw new IllegalArgumentException(
    'No guest user for "' + siteName + '". Create the site first.'
  );
}
Id guestId = guests[0].Id;

// 3. Customer user
Contact customer = [
  SELECT Id, FirstName, LastName, Email
  FROM Contact
  WHERE Email = :customerEmail
  LIMIT 1
];
List<User> existing = [
  SELECT Id, Username
  FROM User
  WHERE ContactId = :customer.Id
];
Id customerId;
if (existing.isEmpty()) {
  User u = new User(
    Username = 'priya.raman.' + UserInfo.getOrganizationId() + '@example.com',
    FirstName = customer.FirstName,
    LastName = customer.LastName,
    Email = customer.Email,
    Alias = 'praman',
    CommunityNickname = 'priya.raman.' + UserInfo.getOrganizationId().right(6),
    ContactId = customer.Id,
    ProfileId = [SELECT Id FROM Profile WHERE Name = :customerProfile]
    .Id,
    TimeZoneSidKey = 'America/New_York',
    LocaleSidKey = 'en_US',
    EmailEncodingKey = 'UTF-8',
    LanguageLocaleKey = 'en_US'
  );
  insert u;
  customerId = u.Id;
  System.debug('SETUP customer: created ' + u.Username);
} else {
  customerId = existing[0].Id;
  System.debug('SETUP customer: already exists, ' + existing[0].Username);
}

Map<Id, List<String>> wanted = new Map<Id, List<String>>{
  guestId => new List<String>{ 'Site_Search_Kit_User', 'Support_Demo_Guest' },
  customerId => new List<String>{ 'Site_Search_Kit_User', 'Support_Demo_User' }
};
// Permission sets for both users, skipping ones already assigned.
List<PermissionSetAssignment> toAssign = new List<PermissionSetAssignment>();
Set<String> assigned = new Set<String>();
for (PermissionSetAssignment psa : [
  SELECT AssigneeId, PermissionSetId
  FROM PermissionSetAssignment
  WHERE AssigneeId IN :wanted.keySet() AND PermissionSetId IN :permSets.values()
]) {
  assigned.add(psa.AssigneeId + ':' + psa.PermissionSetId);
}
for (Id userId : wanted.keySet()) {
  for (String name : wanted.get(userId)) {
    Id psId = permSets.get(name);
    if (!assigned.contains(userId + ':' + psId)) {
      toAssign.add(
        new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = psId)
      );
    }
  }
}
insert toAssign;
System.debug(
  'SETUP permission sets: ' + toAssign.size() + ' new assignment(s)'
);

// Values the Node wrapper needs for the site membership record.
Id networkId = [SELECT Id FROM Network WHERE Name = :siteName].Id;
Id profileId = [SELECT Id FROM Profile WHERE Name = :customerProfile].Id;
Boolean isMember = ![
    SELECT Id
    FROM NetworkMemberGroup
    WHERE NetworkId = :networkId AND ParentId = :profileId
  ]
  .isEmpty();
System.debug(
  'SETUP_MEMBERSHIP ' + networkId + ' ' + profileId + ' ' + isMember
);
