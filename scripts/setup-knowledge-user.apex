// Demo only: makes the running user a Knowledge user. Run once on a new demo org before the
// first deploy (README step 5): deploying Knowledge settings (the Spanish article language)
// fails with "insufficient access rights on entity: KnowledgeLanguageConfig" otherwise.
// Safe to run more than once.
User me = [
  SELECT Id, UserPermissionsKnowledgeUser
  FROM User
  WHERE Id = :UserInfo.getUserId()
];
if (!me.UserPermissionsKnowledgeUser) {
  me.UserPermissionsKnowledgeUser = true;
  update me;
}
System.debug('SETUP knowledge user: ' + UserInfo.getUserName());
