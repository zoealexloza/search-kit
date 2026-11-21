@IsTest
private class SearchConfigPicklistTest {
  @IsTest
  static void listsOnlyActiveConfigsSortedByLabel() {
    Search_Config__mdt zeta = SearchTestFactory.config('Zeta', true, null);
    Search_Config__mdt alpha = SearchTestFactory.config('Alpha', true, null);
    Search_Config__mdt inactive = SearchTestFactory.config(
      'Inactive',
      false,
      null
    );
    zeta.Label = 'Zeta Search';
    alpha.Label = 'Alpha Search';
    SearchTestFactory.register(new List<SObject>{ zeta, inactive, alpha });

    List<VisualEditor.DataRow> rows = new SearchConfigPicklist()
      .getValues()
      .getDataRows();

    Assert.areEqual(2, rows.size(), 'Inactive config must not be listed');
    Assert.areEqual('Alpha Search', rows[0].getLabel());
    Assert.areEqual('Alpha', rows[0].getValue());
    Assert.areEqual('Zeta Search', rows[1].getLabel());
    Assert.areEqual('Zeta', rows[1].getValue());
  }

  @IsTest
  static void sameLabelsSortByDeveloperName() {
    Search_Config__mdt second = SearchTestFactory.config(
      'B_Config',
      true,
      null
    );
    Search_Config__mdt first = SearchTestFactory.config('A_Config', true, null);
    second.Label = 'Search';
    first.Label = 'Search';
    SearchTestFactory.register(new List<SObject>{ second, first });

    List<Search_Config__mdt> active = new SearchConfigProvider()
      .getActiveConfigs();

    Assert.areEqual('A_Config', active[0].DeveloperName);
    Assert.areEqual('B_Config', active[1].DeveloperName);
  }

  @IsTest
  static void defaultsToTheOnlyActiveConfig() {
    SearchTestFactory.register(
      new List<SObject>{
        SearchTestFactory.config('Only_One', true, null),
        SearchTestFactory.config('Off', false, null)
      }
    );

    VisualEditor.DataRow defaultRow = new SearchConfigPicklist()
      .getDefaultValue();

    Assert.isNotNull(
      defaultRow,
      'A single active config should be preselected'
    );
    Assert.areEqual('Only_One', defaultRow.getValue());
  }

  @IsTest
  static void noDefaultWhenSeveralConfigsAreActive() {
    SearchTestFactory.register(
      new List<SObject>{
        SearchTestFactory.config('One', true, null),
        SearchTestFactory.config('Two', true, null)
      }
    );

    Assert.isNull(
      new SearchConfigPicklist().getDefaultValue(),
      'The admin must choose when several configs are active'
    );
  }

  @IsTest
  static void emptyWhenNoConfigIsActive() {
    SearchTestFactory.register(
      new List<SObject>{ SearchTestFactory.config('Off', false, null) }
    );

    SearchConfigPicklist picklist = new SearchConfigPicklist();

    Assert.isNull(picklist.getDefaultValue());
    Assert.areEqual(0, picklist.getValues().size());
  }
}
