@IsTest
private class FacetServiceTest {
  private static List<SearchTarget> targets() {
    SearchConfig.ObjectConfig accountConfig = new SearchConfig.ObjectConfig();
    accountConfig.developerName = 'Accounts';
    accountConfig.objectApiName = 'Account';
    accountConfig.titleField = 'Name';
    accountConfig.facets.add(facet('Industry', 'Sector'));
    accountConfig.facets.add(facet('Rating', null));

    SearchConfig.ObjectConfig caseConfig = new SearchConfig.ObjectConfig();
    caseConfig.developerName = 'Cases';
    caseConfig.objectApiName = 'Case';
    caseConfig.titleField = 'Subject';
    caseConfig.facets.add(facet('IsEscalated', 'Escalated'));

    return new SchemaValidator()
      .validateAll(
        new List<SearchConfig.ObjectConfig>{ accountConfig, caseConfig }
      );
  }

  /** Resolves a selection of one Industry value plus the given IsEscalated values. */
  private static Map<String, Map<String, List<Object>>> selectIndustryAndEscalated(
    FacetService service,
    List<SearchTarget> targets,
    String industry,
    List<String> escalated
  ) {
    return service.resolveSelections(
      targets,
      new List<SearchRequestDto.FacetSelection>{
        SearchTestFactory.selection(
          'Account',
          'Industry',
          new List<String>{ industry }
        ),
        SearchTestFactory.selection('Case', 'IsEscalated', escalated)
      }
    );
  }

  private static SearchConfig.FacetConfig facet(String field, String label) {
    SearchConfig.FacetConfig facet = new SearchConfig.FacetConfig();
    facet.developerName = field;
    facet.fieldApiName = field;
    facet.label = label;
    return facet;
  }

  @IsTest
  static void resolveSelectionsKeepsOnlyConfiguredFacetsAndActiveValues() {
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      2
    );
    List<SearchRequestDto.FacetSelection> selections = new List<SearchRequestDto.FacetSelection>{
      SearchTestFactory.selection(
        'ACCOUNT',
        'industry',
        new List<String>{
          industries[0].toUpperCase(),
          'Bogus',
          industries[0],
          industries[1]
        }
      ),
      SearchTestFactory.selection(
        'Account',
        'Phone',
        new List<String>{ '555' }
      ), // not a configured facet
      SearchTestFactory.selection(
        'Opportunity',
        'StageName',
        new List<String>{ 'x' }
      ), // not a configured object
      SearchTestFactory.selection(
        'Case',
        'IsEscalated',
        new List<String>{ 'true', 'yes' }
      ),
      SearchTestFactory.selection(
        'Account',
        'Rating',
        new List<String>{ 'Bogus only' }
      ), // nothing valid left
      SearchTestFactory.selection(
        null,
        'Industry',
        new List<String>{ industries[0] }
      ),
      SearchTestFactory.selection(
        'Account',
        null,
        new List<String>{ industries[0] }
      ),
      SearchTestFactory.selection('Account', 'Industry', null),
      null
    };

    Map<String, Map<String, List<Object>>> resolved = new FacetService()
      .resolveSelections(targets(), selections);

    Assert.areEqual(new Set<String>{ 'account', 'case' }, resolved.keySet());
    Assert.areEqual(
      new List<Object>{ industries[0], industries[1] },
      resolved.get('account').get('industry'),
      'Canonical, de-duplicated, invalid dropped'
    );
    Assert.isFalse(
      resolved.get('account').containsKey('rating'),
      'Selection with no valid values is left out'
    );
    Assert.areEqual(
      new List<Object>{ true },
      resolved.get('case').get('isescalated')
    );
  }

  @IsTest
  static void resolveSelectionsMergesRepeatedFacets() {
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      2
    );
    List<SearchRequestDto.FacetSelection> selections = new List<SearchRequestDto.FacetSelection>{
      SearchTestFactory.selection(
        'Account',
        'Industry',
        new List<String>{ industries[0] }
      ),
      SearchTestFactory.selection(
        'Account',
        'Industry',
        new List<String>{ industries[1], industries[0] }
      )
    };

    Map<String, Map<String, List<Object>>> resolved = new FacetService()
      .resolveSelections(targets(), selections);

    Assert.areEqual(
      new List<Object>{ industries[0], industries[1] },
      resolved.get('account').get('industry')
    );
  }

  @IsTest
  static void resolveSelectionsHandlesNullAndOversizedInput() {
    FacetService service = new FacetService();
    Assert.isTrue(service.resolveSelections(targets(), null).isEmpty());

    String industry = SearchTestFactory.picklistValues(Account.Industry, 1)[0];
    List<String> manyValues = new List<String>();
    for (Integer i = 0; i < FacetService.MAX_VALUES_PER_SELECTION; i++) {
      manyValues.add('junk ' + i);
    }
    manyValues.add(industry); // beyond the cap: ignored
    List<SearchRequestDto.FacetSelection> selections = new List<SearchRequestDto.FacetSelection>();
    for (Integer i = 0; i < FacetService.MAX_SELECTIONS; i++) {
      selections.add(
        SearchTestFactory.selection(
          'Account',
          'Industry',
          new List<String>{ 'junk' }
        )
      );
    }
    selections.add(
      SearchTestFactory.selection(
        'Account',
        'Industry',
        new List<String>{ industry }
      )
    ); // beyond the cap
    selections.add(
      0,
      SearchTestFactory.selection('Account', 'Rating', manyValues)
    );

    Map<String, Map<String, List<Object>>> resolved = service.resolveSelections(
      targets(),
      selections
    );

    Assert.isTrue(
      resolved.isEmpty(),
      'Values and selections beyond the caps are ignored: ' + resolved
    );
  }

  @IsTest
  static void toConditionsBuildsOneConditionPerRestrictingFacet() {
    String industry = SearchTestFactory.picklistValues(Account.Industry, 1)[0];
    List<SearchTarget> targets = targets();
    FacetService service = new FacetService();
    Map<String, Map<String, List<Object>>> resolved = selectIndustryAndEscalated(
      service,
      targets,
      industry,
      new List<String>{ 'true', 'false' }
    );

    Map<String, List<SearchQueryBuilder.Condition>> conditions = service.toConditions(
      targets,
      resolved
    );

    Assert.areEqual(
      new Set<String>{ 'account' },
      conditions.keySet(),
      'Both checkbox values selected restricts nothing'
    );
    Assert.areEqual('Industry', conditions.get('account')[0].fieldName);
    Assert.areEqual('IN', conditions.get('account')[0].operator);
  }

  @IsTest
  static void describeFacetsListsValuesAndMarksSelections() {
    String industry = SearchTestFactory.picklistValues(Account.Industry, 1)[0];
    List<SearchTarget> targets = targets();
    FacetService service = new FacetService();
    Map<String, Map<String, List<Object>>> resolved = selectIndustryAndEscalated(
      service,
      targets,
      industry,
      new List<String>{ 'false' }
    );

    List<SearchResponseDto.FacetGroup> groups = service.describeFacets(
      targets,
      resolved
    );

    Assert.areEqual(3, groups.size());
    SearchResponseDto.FacetGroup industryGroup = groups[0];
    Assert.areEqual('Account', industryGroup.objectApiName);
    Assert.areEqual('Industry', industryGroup.fieldApiName);
    Assert.areEqual('Sector', industryGroup.label);
    Integer activeCount = 0;
    for (
      Schema.PicklistEntry entry : Account.Industry.getDescribe()
        .getPicklistValues()
    ) {
      activeCount += entry.isActive() ? 1 : 0;
    }
    Assert.areEqual(activeCount, industryGroup.values.size());
    for (SearchResponseDto.FacetValue value : industryGroup.values) {
      Assert.areEqual(
        value.value == industry,
        value.selected,
        'Only the chosen value is selected: ' + value.value
      );
    }
    Assert.areEqual(Account.Rating.getDescribe().getLabel(), groups[1].label);

    SearchResponseDto.FacetGroup checkboxGroup = groups[2];
    Assert.areEqual(2, checkboxGroup.values.size());
    Assert.areEqual('true', checkboxGroup.values[0].value);
    Assert.areEqual(
      System.Label.Search_Value_Yes,
      checkboxGroup.values[0].label
    );
    Assert.isFalse(checkboxGroup.values[0].selected);
    Assert.areEqual(
      System.Label.Search_Value_No,
      checkboxGroup.values[1].label
    );
    Assert.isTrue(checkboxGroup.values[1].selected);
  }

  // ---- facet values ruled out by filter rules ----

  private static SearchConfig.RuleConfig rule(
    String field,
    String operator,
    String value
  ) {
    SearchConfig.RuleConfig rule = new SearchConfig.RuleConfig();
    rule.developerName = field + '_' + operator;
    rule.fieldApiName = field;
    rule.operator = operator;
    rule.value = value;
    return rule;
  }

  /** Account target with an Industry facet and the given filter rules. */
  private static SearchTarget filteredAccounts(
    List<SearchConfig.RuleConfig> rules
  ) {
    SearchConfig.ObjectConfig config = new SearchConfig.ObjectConfig();
    config.developerName = 'Accounts';
    config.objectApiName = 'Account';
    config.titleField = 'Name';
    config.facets.add(facet('Industry', null));
    config.filterRules.addAll(rules);
    SearchTarget target = new SchemaValidator().validate(config);
    Assert.isNotNull(target, 'Test config should be valid');
    return target;
  }

  private static List<String> offered(SearchTarget target) {
    List<String> values = new List<String>();
    for (
      SearchResponseDto.FacetGroup facetGroup : new FacetService()
        .describeFacets(
          new List<SearchTarget>{ target },
          new Map<String, Map<String, List<Object>>>()
        )
    ) {
      for (SearchResponseDto.FacetValue value : facetGroup.values) {
        values.add(value.value);
      }
    }
    return values;
  }

  @IsTest
  static void filterRulesRemoveImpossibleFacetValues() {
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      3
    );
    Integer allCount = offered(
        filteredAccounts(new List<SearchConfig.RuleConfig>())
      )
      .size();

    Assert.areEqual(
      new List<String>{ industries[0], industries[2] },
      offered(
        filteredAccounts(
          new List<SearchConfig.RuleConfig>{
            rule('Industry', 'in', industries[2] + ';' + industries[0])
          }
        )
      ),
      'in keeps only the listed values, in picklist order'
    );
    Assert.areEqual(
      new List<String>{ industries[1] },
      offered(
        filteredAccounts(
          new List<SearchConfig.RuleConfig>{
            rule('Industry', 'equals', industries[1])
          }
        )
      )
    );
    List<String> withoutFirst = offered(
      filteredAccounts(
        new List<SearchConfig.RuleConfig>{
          rule('Industry', 'not_equals', industries[0])
        }
      )
    );
    Assert.areEqual(allCount - 1, withoutFirst.size());
    Assert.isFalse(withoutFirst.contains(industries[0]));
    Assert.areEqual(
      new List<String>{ industries[1] },
      offered(
        filteredAccounts(
          new List<SearchConfig.RuleConfig>{
            rule('Industry', 'in', industries[0] + ';' + industries[1]),
            rule('Industry', 'not_equals', industries[0])
          }
        )
      ),
      'Several rules on the field are all applied'
    );
    Assert.areEqual(
      allCount,
      offered(
          filteredAccounts(
            new List<SearchConfig.RuleConfig>{
              rule('Industry', 'is_not_blank', null),
              rule('Name', 'not_equals', 'Acme')
            }
          )
        )
        .size(),
      'Rules that rule out no single value, or are on other fields, change nothing'
    );
  }

  @IsTest
  static void facetWithNothingLeftIsHidden() {
    List<SearchResponseDto.FacetGroup> groups = new FacetService()
      .describeFacets(
        new List<SearchTarget>{
          filteredAccounts(
            new List<SearchConfig.RuleConfig>{
              rule('Industry', 'is_blank', null)
            }
          )
        },
        new Map<String, Map<String, List<Object>>>()
      );
    Assert.isTrue(groups.isEmpty(), 'No empty facet group is returned');
  }

  @IsTest
  static void checkboxFacetKeepsTheValueAFilterAllows() {
    SearchConfig.ObjectConfig config = new SearchConfig.ObjectConfig();
    config.developerName = 'Cases';
    config.objectApiName = 'Case';
    config.titleField = 'Subject';
    config.facets.add(facet('IsEscalated', null));
    config.filterRules.add(rule('IsEscalated', 'is_false', null));
    Assert.areEqual(
      new List<String>{ 'false' },
      offered(new SchemaValidator().validate(config))
    );
  }

  @IsTest
  static void multiSelectFacetIsNotNarrowed() {
    Schema.DescribeFieldResult channel = SearchTestFactory.multiSelectField();
    if (channel == null) {
      return; // QuickText is not available in this org.
    }
    SearchResponseDto.FacetValue email = new SearchResponseDto.FacetValue();
    email.value = 'Email';
    SearchResponseDto.FacetValue phone = new SearchResponseDto.FacetValue();
    phone.value = 'Phone';
    SearchTarget.FieldRule includesEmail = new SearchTarget.FieldRule();
    includesEmail.field = channel;
    includesEmail.operator = SchemaValidator.OP_IN;
    includesEmail.value = new List<Object>{ 'Email' };

    Assert.areEqual(
      2,
      FacetService.withoutExcludedValues(
          new List<SearchResponseDto.FacetValue>{ email, phone },
          channel,
          new List<SearchTarget.FieldRule>{ includesEmail }
        )
        .size(),
      'A record that includes Email may also include Phone'
    );
  }

  @IsTest
  static void selectionsOfExcludedValuesAreIgnored() {
    // For example an old shared link with Status = Closed, after a filter started hiding
    // closed cases.
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      2
    );
    SearchTarget target = filteredAccounts(
      new List<SearchConfig.RuleConfig>{
        rule('Industry', 'not_equals', industries[0])
      }
    );
    Map<String, Map<String, List<Object>>> resolved = new FacetService()
      .resolveSelections(
        new List<SearchTarget>{ target },
        new List<SearchRequestDto.FacetSelection>{
          SearchTestFactory.selection(
            'Account',
            'Industry',
            new List<String>{ industries[0], industries[1] }
          )
        }
      );
    Assert.areEqual(
      new List<Object>{ industries[1] },
      resolved.get('account').get('industry')
    );

    Map<String, Map<String, List<Object>>> onlyExcluded = new FacetService()
      .resolveSelections(
        new List<SearchTarget>{ target },
        new List<SearchRequestDto.FacetSelection>{
          SearchTestFactory.selection(
            'Account',
            'Industry',
            new List<String>{ industries[0] }
          )
        }
      );
    Assert.isTrue(
      onlyExcluded.isEmpty(),
      'Nothing left to select, so no browse query runs'
    );
  }

  // ---- facet Values allowlist ----

  private static SearchTarget industryTarget(String values) {
    SearchConfig.ObjectConfig config = new SearchConfig.ObjectConfig();
    config.developerName = 'Accounts';
    config.objectApiName = 'Account';
    config.titleField = 'Name';
    SearchConfig.FacetConfig industry = facet('Industry', null);
    industry.values = values;
    config.facets.add(industry);
    return new SchemaValidator().validate(config);
  }

  @IsTest
  static void configuredValuesAreOfferedInTheirOrder() {
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      3
    );
    SearchTarget target = industryTarget(industries[2] + ';' + industries[0]);

    List<SearchResponseDto.FacetGroup> groups = new FacetService()
      .describeFacets(
        new List<SearchTarget>{ target },
        new Map<String, Map<String, List<Object>>>()
      );

    Assert.areEqual(1, groups.size());
    Assert.areEqual(2, groups[0].values.size());
    Assert.areEqual(industries[2], groups[0].values[0].value);
    Assert.areEqual(industries[0], groups[0].values[1].value);
  }

  @IsTest
  static void selectionsOutsideTheConfiguredValuesAreIgnored() {
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      2
    );
    List<SearchTarget> targets = new List<SearchTarget>{
      industryTarget(industries[0])
    };
    FacetService service = new FacetService();

    Map<String, Map<String, List<Object>>> resolved = service.resolveSelections(
      targets,
      new List<SearchRequestDto.FacetSelection>{
        SearchTestFactory.selection('Account', 'Industry', industries)
      }
    );

    Assert.areEqual(
      new List<Object>{ industries[0] },
      resolved.get('account').get('industry'),
      'A value not in the list (e.g. from an edited URL) is dropped'
    );
  }

  @IsTest
  static void filterRulesStillNarrowConfiguredValues() {
    List<String> industries = SearchTestFactory.picklistValues(
      Account.Industry,
      2
    );
    SearchTarget target = industryTarget(industries[0] + ';' + industries[1]);
    SearchTarget.FieldRule rule = new SearchTarget.FieldRule();
    rule.field = Account.Industry.getDescribe();
    rule.operator = 'not_equals';
    rule.value = industries[0];
    target.filterRules.add(rule);

    List<SearchResponseDto.FacetGroup> groups = new FacetService()
      .describeFacets(
        new List<SearchTarget>{ target },
        new Map<String, Map<String, List<Object>>>()
      );

    Assert.areEqual(1, groups[0].values.size());
    Assert.areEqual(industries[1], groups[0].values[0].value);
  }
}
