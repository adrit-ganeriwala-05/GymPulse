// Calendar rules shared by the streak datasource and the Home screen.
// Pure Dart — no Flutter, no packages — so both data and presentation may
// import it without violating the dependency rule.

/// Rest days allotted per calendar week. The single source of truth for the
/// "2" that was previously duplicated across the datasource and the UI.
const int kRestDaysPerWeek = 2;

/// Training days implied by the allowance. Drives the weekly progress bar.
const int kTrainingDaysPerWeek = 7 - kRestDaysPerWeek;

/// Truncates to local midnight (civil date). Never compare instants when you
/// mean to compare days.
DateTime civilDate(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole calendar days from [a] to [b], DST-safe.
///
/// `DateTime.difference().inDays` divides *elapsed* time by 24h, so two local
/// midnights across a spring-forward are 23h apart and report 0. Projecting
/// both onto UTC (which has no DST) makes every day exactly 24h by
/// construction. The UTC values are never displayed or stored.
int civilDaysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;

bool isSameCivilDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Monday 00:00 local of the ISO week containing [d].
///
/// Built from components rather than `subtract(Duration(days:))` because a
/// Duration subtraction across a DST boundary lands an hour off midnight.
/// The DateTime constructor normalises a day of 0 or negative into the
/// previous month.
DateTime startOfWeek(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));
