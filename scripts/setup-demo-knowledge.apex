// Demo only: creates and publishes the demo Knowledge articles, in English and Spanish, with
// data categories (group Products) and channels. Creates only articles that don't exist yet
// (matched by URL name), so it is safe to run more than once. Run through
// scripts/setup-demo-users.js, after setup-demo-users.apex has made the running user a
// Knowledge user (a separate transaction: users and articles can't be changed in one).
//
// The set covers what the search must keep out: a draft, an archived version, an internal-only
// article and a customer-only article, next to published articles for guests and customers.
// Channels: guest = public knowledge base (IsVisibleInPkb), customer = IsVisibleInCsp; the
// internal app channel is always on.

final String GUEST = 'guest';
final String CUSTOMER = 'customer';
final String INTERNAL = 'internal';
final String PUBLISH = 'publish';
final String DRAFT = 'draft';
final String ARCHIVE = 'archive';

// URL name => title, summary, language, category, audience, final state
List<List<String>> articles = new List<List<String>>{
  new List<String>{ 'kb-nimbus-reset-password', 'Reset your Nimbus Cloud password', 'Use the sign-in page link to get a reset email, then choose a new password.', 'en_US', 'Nimbus_Cloud', GUEST, PUBLISH },
  new List<String>{ 'kb-nimbus-two-factor', 'Set up two-factor sign-in for Nimbus Cloud', 'Add an authenticator app so a code is needed with your password.', 'en_US', 'Nimbus_Cloud', GUEST, PUBLISH },
  new List<String>{ 'kb-atlas-offline-sync', 'Sync Atlas Mobile data offline', 'Atlas Mobile keeps changes on the device and syncs them when you are back online.', 'en_US', 'Atlas_Mobile', GUEST, PUBLISH },
  new List<String>{ 'kb-beacon-export-reports', 'Export Beacon Analytics reports to CSV', 'Download any report as a CSV file from the report menu.', 'en_US', 'Beacon_Analytics', GUEST, PUBLISH },
  new List<String>{ 'kb-business-password-policy', 'Password policy for business accounts', 'Customers only: password length, expiry and reuse rules for business plans.', 'en_US', '', CUSTOMER, PUBLISH },
  new List<String>{ 'kb-internal-password-escalation', 'Escalate a password reset to tier 2', 'Internal only: when and how support agents escalate a locked account.', 'en_US', 'Nimbus_Cloud', INTERNAL, PUBLISH },
  new List<String>{ 'kb-passwordless-preview', 'Coming soon: passwordless sign-in', 'Draft, never published: an upcoming password change.', 'en_US', 'Nimbus_Cloud', GUEST, DRAFT },
  new List<String>{ 'kb-old-password-rules', 'Old password rules (2024)', 'Archived: the password rules before the current policy.', 'en_US', 'Nimbus_Cloud', GUEST, ARCHIVE },
  new List<String>{ 'kb-es-restablecer-contrasena', 'Restablecer la contraseña de Nimbus Cloud', 'Usa el enlace de la página de inicio de sesión para recibir un correo y elegir una contraseña nueva.', 'es', 'Nimbus_Cloud', GUEST, PUBLISH },
  new List<String>{ 'kb-es-sincronizar-atlas', 'Sincronizar datos de Atlas Mobile sin conexión', 'Atlas Mobile guarda los cambios en el dispositivo y los sincroniza al volver a conectarte.', 'es', 'Atlas_Mobile', GUEST, PUBLISH },
  new List<String>{ 'kb-es-exportar-beacon', 'Exportar informes de Beacon Analytics a CSV', 'Descarga cualquier informe como archivo CSV desde el menú del informe.', 'es', 'Beacon_Analytics', GUEST, PUBLISH }
};

Set<String> urlNames = new Set<String>();
for (List<String> article : articles) {
  urlNames.add(article[0]);
}
Set<String> existing = new Set<String>();
for (Knowledge__kav version : [
  SELECT UrlName
  FROM Knowledge__kav
  WHERE UrlName IN :urlNames
]) {
  existing.add(version.UrlName);
}

List<Knowledge__kav> created = new List<Knowledge__kav>();
List<List<String>> createdSpecs = new List<List<String>>();
for (List<String> article : articles) {
  if (existing.contains(article[0])) {
    continue;
  }
  String audience = article[5];
  created.add(
    new Knowledge__kav(
      UrlName = article[0],
      Title = article[1],
      Summary = article[2],
      Language = article[3],
      IsVisibleInPkb = audience == GUEST,
      IsVisibleInCsp = audience == GUEST || audience == CUSTOMER
    )
  );
  createdSpecs.add(article);
}
insert created;

// Categories must be set while the article is still a draft.
List<Knowledge__DataCategorySelection> categories = new List<Knowledge__DataCategorySelection>();
for (Integer i = 0; i < created.size(); i++) {
  if (String.isNotBlank(createdSpecs[i][4])) {
    categories.add(
      new Knowledge__DataCategorySelection(
        ParentId = created[i].Id,
        DataCategoryGroupName = 'Products',
        DataCategoryName = createdSpecs[i][4]
      )
    );
  }
}
insert categories;

Map<Id, Id> articleIdByVersion = new Map<Id, Id>();
for (Knowledge__kav version : [
  SELECT Id, KnowledgeArticleId
  FROM Knowledge__kav
  WHERE Id IN :created
]) {
  articleIdByVersion.put(version.Id, version.KnowledgeArticleId);
}
Integer published = 0;
Integer archived = 0;
for (Integer i = 0; i < created.size(); i++) {
  String state = createdSpecs[i][6];
  if (state == DRAFT) {
    continue;
  }
  Id articleId = articleIdByVersion.get(created[i].Id);
  KbManagement.PublishingService.publishArticle(articleId, true);
  published++;
  if (state == ARCHIVE) {
    KbManagement.PublishingService.archiveOnlineArticle(articleId, null);
    archived++;
  }
}
System.debug(
  'SETUP knowledge articles: ' +
    created.size() +
    ' created (' +
    published +
    ' published, ' +
    archived +
    ' of them then archived), ' +
    existing.size() +
    ' already there'
);
