/**
 * Test data for the search classes.
 *
 * Custom Metadata records cannot be inserted in tests, so config records are built in memory
 * (with fake Ids, linked by Id exactly as getAll() links them) and handed to
 * SearchConfigProvider through its @TestVisible lists.
 *
 * Tests only use standard objects (Account, Contact, Case) so they run in any org, including
 * the packaging org, where the demo's Help_Article__c does not exist.
 */
@IsTest
public class SearchTestFactory {
  public static final String CONFIG_NAME = 'Test_Config';
  /** Standard object with a standard multi-select picklist (Channel). Not in every org. */
  public static final String MULTI_SELECT_OBJECT = 'QuickText';
  public static final String MULTI_SELECT_FIELD = 'Channel';

  private static Integer idCounter = 0;

  /**
   * Builds a config record.
   * @param developerName DeveloperName
   * @param isActive Is_Active__c
   * @param resultsPerObject Results_Per_Object__c (may be null)
   */
  public static Search_Config__mdt config(
    String developerName,
    Boolean isActive,
    Decimal resultsPerObject
  ) {
    return new Search_Config__mdt(
      Id = fakeId(Search_Config__mdt.SObjectType),
      DeveloperName = developerName,
      Label = developerName,
      Is_Active__c = isActive,
      Results_Per_Object__c = resultsPerObject
    );
  }

  /**
   * Builds an active Search Object record linked to its config by Id.
   * @param details up to three detail field names (may be null)
   */
  public static Search_Object__mdt searchObject(
    Search_Config__mdt parent,
    String developerName,
    String objectApiName,
    String titleField,
    List<String> details,
    Decimal sortOrder
  ) {
    List<String> slots = details == null ? new List<String>() : details;
    return new Search_Object__mdt(
      Id = fakeId(Search_Object__mdt.SObjectType),
      DeveloperName = developerName,
      Label = developerName,
      Search_Config__c = parent.Id,
      Object__c = objectApiName,
      Title_Field__c = titleField,
      Detail_Field_1__c = slots.size() > 0 ? slots[0] : null,
      Detail_Field_2__c = slots.size() > 1 ? slots[1] : null,
      Detail_Field_3__c = slots.size() > 2 ? slots[2] : null,
      Icon_Name__c = 'standard:record',
      Sort_Order__c = sortOrder,
      Is_Active__c = true
    );
  }

  /** Builds a filter rule linked to its Search Object by Id. */
  public static Search_Filter_Rule__mdt filterRule(
    Search_Object__mdt parent,
    String fieldApiName,
    String operator,
    String value
  ) {
    return new Search_Filter_Rule__mdt(
      Id = fakeId(Search_Filter_Rule__mdt.SObjectType),
      DeveloperName = 'Filter_' + idCounter,
      Search_Object__c = parent.Id,
      Field__c = fieldApiName,
      Operator__c = operator,
      Value__c = value
    );
  }

  /** Builds a boost rule linked to its Search Object by Id. */
  public static Search_Boost_Rule__mdt boostRule(
    Search_Object__mdt parent,
    String fieldApiName,
    String operator,
    String value,
    Decimal points
  ) {
    return new Search_Boost_Rule__mdt(
      Id = fakeId(Search_Boost_Rule__mdt.SObjectType),
      DeveloperName = 'Boost_' + idCounter,
      Search_Object__c = parent.Id,
      Field__c = fieldApiName,
      Operator__c = operator,
      Value__c = value,
      Points__c = points
    );
  }

  /** Builds a facet linked to its Search Object by Id. */
  public static Search_Facet__mdt facet(
    Search_Object__mdt parent,
    String fieldApiName,
    String label,
    Decimal sortOrder
  ) {
    return new Search_Facet__mdt(
      Id = fakeId(Search_Facet__mdt.SObjectType),
      DeveloperName = 'Facet_' + idCounter,
      Search_Object__c = parent.Id,
      Field__c = fieldApiName,
      Label__c = label,
      Sort_Order__c = sortOrder
    );
  }

  /**
   * Makes SearchConfigProvider read these records instead of getAll(). Replaces anything
   * registered before; types with no records get an empty list.
   */
  public static void register(List<SObject> records) {
    SearchConfigProvider.configRecords = new List<Search_Config__mdt>();
    SearchConfigProvider.objectRecords = new List<Search_Object__mdt>();
    SearchConfigProvider.filterRuleRecords = new List<Search_Filter_Rule__mdt>();
    SearchConfigProvider.boostRuleRecords = new List<Search_Boost_Rule__mdt>();
    SearchConfigProvider.facetRecords = new List<Search_Facet__mdt>();
    for (SObject record : records) {
      if (record instanceof Search_Config__mdt) {
        SearchConfigProvider.configRecords.add((Search_Config__mdt) record);
      } else if (record instanceof Search_Object__mdt) {
        SearchConfigProvider.objectRecords.add((Search_Object__mdt) record);
      } else if (record instanceof Search_Filter_Rule__mdt) {
        SearchConfigProvider.filterRuleRecords.add(
          (Search_Filter_Rule__mdt) record
        );
      } else if (record instanceof Search_Boost_Rule__mdt) {
        SearchConfigProvider.boostRuleRecords.add(
          (Search_Boost_Rule__mdt) record
        );
      } else if (record instanceof Search_Facet__mdt) {
        SearchConfigProvider.facetRecords.add((Search_Facet__mdt) record);
      }
    }
  }

  /** A request for CONFIG_NAME with the given term and no facets. */
  public static SearchRequestDto request(String searchTerm) {
    SearchRequestDto request = new SearchRequestDto();
    request.configName = CONFIG_NAME;
    request.searchTerm = searchTerm;
    request.selectedFacets = new List<SearchRequestDto.FacetSelection>();
    return request;
  }

  /** One facet selection. */
  public static SearchRequestDto.FacetSelection selection(
    String objectApiName,
    String fieldApiName,
    List<String> values
  ) {
    SearchRequestDto.FacetSelection selection = new SearchRequestDto.FacetSelection();
    selection.objectApiName = objectApiName;
    selection.fieldApiName = fieldApiName;
    selection.values = values;
    return selection;
  }

  /**
   * The first active values of a picklist, read from describe so tests do not depend on the
   * org's picklist setup.
   */
  public static List<String> picklistValues(
    Schema.SObjectField field,
    Integer count
  ) {
    List<String> values = new List<String>();
    for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
      if (entry.isActive() && values.size() < count) {
        values.add(entry.getValue());
      }
    }
    Assert.areEqual(
      count,
      values.size(),
      'Test needs ' + count + ' active values on ' + field
    );
    return values;
  }

  /**
   * Describes QuickText, which has a standard multi-select picklist (Channel). Standard objects
   * have few multi-select picklists, and QuickText is not available in every org, so it is
   * looked up by name (a static reference would stop the tests compiling there). Tests that
   * need it skip those cases when this returns null.
   * @return the describe result, or null if QuickText is not available
   */
  public static Schema.DescribeSObjectResult multiSelectObject() {
    try {
      return Schema.describeSObjects(
        new List<String>{ MULTI_SELECT_OBJECT },
        SObjectDescribeOptions.DEFERRED
      )[0];
    } catch (InvalidParameterValueException e) {
      return null;
    }
  }

  /**
   * The Channel multi-select picklist on QuickText.
   * @return the describe result, or null if QuickText is not available
   */
  public static Schema.DescribeFieldResult multiSelectField() {
    Schema.DescribeSObjectResult quickText = multiSelectObject();
    return quickText == null
      ? null
      : quickText.fields.getMap().get(MULTI_SELECT_FIELD).getDescribe();
  }

  /**
   * Inserts a user on the Minimum Access - Salesforce profile: no object permissions, the
   * closest internal stand-in for a guest user. Optionally grants Read on Account (and FLS on
   * no Account fields beyond those always readable) through a new permission set.
   */
  public static User minimumAccessUser(Boolean withAccountRead) {
    Profile profile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ];
    String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    User user = new User(
      ProfileId = profile.Id,
      LastName = 'Search Test',
      Alias = 'srchtst',
      Email = 'search.test@example.com',
      Username = 'search.test.' + unique + '@example.com',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'America/Los_Angeles'
    );
    // Setup objects in their own runAs block to avoid mixed DML with test data.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert user;
      if (withAccountRead) {
        PermissionSet permissionSet = new PermissionSet(
          Name = 'Search_Test_' + unique.left(10),
          Label = 'Search Test ' + unique.left(10)
        );
        insert permissionSet;
        insert new ObjectPermissions(
          ParentId = permissionSet.Id,
          SobjectType = 'Account',
          PermissionsRead = true
        );
        insert new PermissionSetAssignment(
          AssigneeId = user.Id,
          PermissionSetId = permissionSet.Id
        );
      }
    }
    return user;
  }

  private static Id fakeId(Schema.SObjectType type) {
    idCounter++;
    return Id.valueOf(
      type.getDescribe().getKeyPrefix() +
      String.valueOf(idCounter).leftPad(12, '0')
    );
  }
}
