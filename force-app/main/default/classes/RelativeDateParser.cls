/**
 * Resolves relative date values in filter and boost rules (TODAY, YESTERDAY, LAST_N_DAYS:n,
 * NEXT_N_DAYS:n) to one calendar day, in the running user's time zone.
 *
 * The names match SOQL date literals, but each value means a single day, not a range:
 * LAST_N_DAYS:30 is the day 30 days before today. The rule's operator does the comparing, so
 * "Published Date greater_than LAST_N_DAYS:30" means "published in the last 30 days, today
 * included". Resolving to a day means queries can bind a plain Date and boost rules can compare
 * with it in Apex, so both always agree.
 *
 * Strict allowlist: the whole value must match one of the four forms, n is 0 to 9999, and
 * nothing else is accepted. The resolved Date reaches the query, never the configured text.
 *
 * inherited sharing: pure logic, no queries or DML.
 */
public inherited sharing class RelativeDateParser {
  /** Largest n accepted in LAST_N_DAYS:n and NEXT_N_DAYS:n (about 27 years). */
  public static final Integer MAX_DAYS = 9999;

  private static final Pattern RELATIVE_DATE = Pattern.compile(
    '^(TODAY|YESTERDAY|(LAST|NEXT)_N_DAYS:(\\d{1,4}))$'
  );

  /** Fixed "today" for tests; null means Date.today(). */
  @TestVisible
  private static Date todayOverride;

  /**
   * Resolves a relative date value.
   * @param rawValue the configured value, any case, surrounding spaces ignored
   * @return the day it stands for, or null if it is not a relative date value
   */
  public static Date resolve(String rawValue) {
    if (String.isBlank(rawValue)) {
      return null;
    }
    Matcher matcher = RELATIVE_DATE.matcher(rawValue.trim().toUpperCase());
    if (!matcher.matches()) {
      return null;
    }
    Date today = today();
    String token = matcher.group(1);
    if (token == 'TODAY') {
      return today;
    }
    if (token == 'YESTERDAY') {
      return today.addDays(-1);
    }
    // At most four digits, so the value always fits an Integer.
    Integer days = Integer.valueOf(matcher.group(3));
    return matcher.group(2) == 'LAST'
      ? today.addDays(-days)
      : today.addDays(days);
  }

  /**
   * Midnight at the start of a day in the running user's time zone. Used to compare Datetime
   * fields with a resolved day.
   * @param day the day
   * @return the Datetime at 00:00:00.000 local time
   */
  public static Datetime startOfDay(Date day) {
    return Datetime.newInstance(day, Time.newInstance(0, 0, 0, 0));
  }

  /**
   * Today in the running user's time zone (or the test override).
   * @return today's date
   */
  public static Date today() {
    return todayOverride != null ? todayOverride : Date.today();
  }
}
