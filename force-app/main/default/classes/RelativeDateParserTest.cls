@IsTest
private class RelativeDateParserTest {
  // 1 March 2026: LAST_N_DAYS crosses the end of February.
  private static final Date TODAY = Date.newInstance(2026, 3, 1);

  @IsTest
  static void resolvesEachForm() {
    RelativeDateParser.todayOverride = TODAY;
    Map<String, Date> cases = new Map<String, Date>{
      'TODAY' => TODAY,
      'today' => TODAY,
      '  Yesterday ' => Date.newInstance(2026, 2, 28),
      'LAST_N_DAYS:30' => Date.newInstance(2026, 1, 30),
      'last_n_days:1' => Date.newInstance(2026, 2, 28),
      'LAST_N_DAYS:0' => TODAY,
      'NEXT_N_DAYS:7' => Date.newInstance(2026, 3, 8),
      'NEXT_N_DAYS:007' => Date.newInstance(2026, 3, 8),
      'LAST_N_DAYS:9999' => TODAY.addDays(-9999)
    };
    for (String value : cases.keySet()) {
      Assert.areEqual(
        cases.get(value),
        RelativeDateParser.resolve(value),
        'Value: ' + value
      );
    }
  }

  @IsTest
  static void rejectsAnythingElse() {
    RelativeDateParser.todayOverride = TODAY;
    List<String> invalid = new List<String>{
      null,
      '',
      '   ',
      'LAST_N_DAYS:-1',
      'LAST_N_DAYS:+1',
      'LAST_N_DAYS:abc',
      'LAST_N_DAYS:',
      'LAST_N_DAYS',
      'LAST_N_DAYS:1.5',
      'LAST_N_DAYS: 5',
      'LAST_N_DAYS:10000',
      'LAST_N_DAYS:99999999999',
      'NEXT_N_DAYS:5;LAST_N_DAYS:5',
      'LAST_N_WEEKS:2',
      'TOMORROW',
      'TODAY TODAY',
      '2026-03-01',
      // Injection attempts: the whole value must match, so nothing can trail a valid form.
      'LAST_N_DAYS:30 OR Id != null',
      'TODAY\' OR Name != \'',
      'TODAY)',
      'TODAY\nOR Id != null'
    };
    for (String value : invalid) {
      Assert.isNull(RelativeDateParser.resolve(value), 'Value: ' + value);
    }
  }

  @IsTest
  static void todayDefaultsToTheUsersToday() {
    Assert.areEqual(Date.today(), RelativeDateParser.today());
    Assert.areEqual(Date.today(), RelativeDateParser.resolve('TODAY'));
  }

  @IsTest
  static void startOfDayIsLocalMidnight() {
    Datetime start = RelativeDateParser.startOfDay(TODAY);
    Assert.areEqual(TODAY, start.date(), 'Same day in the user\'s time zone');
    Assert.areEqual(0, start.hour());
    Assert.areEqual(0, start.minute());
    Assert.areEqual(0, start.second());
    Assert.areEqual(
      start.addDays(-1),
      RelativeDateParser.startOfDay(TODAY.addDays(-1))
    );
  }
}
