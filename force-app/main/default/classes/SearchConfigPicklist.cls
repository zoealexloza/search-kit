/**
 * Lists active search configurations in the Experience Builder property panel of the
 * searchResults component (datasource="apex://SearchConfigPicklist" in its js-meta.xml).
 *
 * global: Experience Builder calls this class from outside the code; global matches the
 * documented VisualEditor.DynamicPickList pattern and keeps it reachable once the code is in a
 * namespaced managed package. It exposes only config labels and DeveloperNames.
 *
 * inherited sharing: reads Custom Metadata only (through SearchConfigProvider), which sharing
 * does not apply to.
 */
global inherited sharing class SearchConfigPicklist extends VisualEditor.DynamicPickList {
  /**
   * Preselects the only active configuration, so a site with one config needs no choice.
   * @return the single active config, or null when there are none or several
   */
  global override VisualEditor.DataRow getDefaultValue() {
    List<Search_Config__mdt> active = new SearchConfigProvider()
      .getActiveConfigs();
    return active.size() == 1 ? toRow(active[0]) : null;
  }

  /**
   * Returns one row per active configuration: label shown, DeveloperName stored.
   * @return the picklist rows, sorted by label
   */
  global override VisualEditor.DynamicPickListRows getValues() {
    VisualEditor.DynamicPickListRows rows = new VisualEditor.DynamicPickListRows();
    for (
      Search_Config__mdt record : new SearchConfigProvider().getActiveConfigs()
    ) {
      rows.addRow(toRow(record));
    }
    return rows;
  }

  private static VisualEditor.DataRow toRow(Search_Config__mdt record) {
    return new VisualEditor.DataRow(record.Label, record.DeveloperName);
  }
}
