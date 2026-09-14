import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/streak_rules.dart';

abstract class StreakLocalDatasource {
  Future<int> getStreak();
  Future<int> getRestDaysRemaining();
  Future<void> updateStreak();
  Future<void> markRestDay();
}

/// Streak semantics (single source of truth — the Home tiles derive from it):
///
/// * A streak is a run of consecutive civil days each of which is a workout
///   day or an explicitly-marked rest day.
/// * The counter increments once per civil day on which the user *trained*.
///   A rest day keeps the streak alive but does not increment it.
/// * Rest days are allotted per ISO week (Monday–Sunday), [kRestDaysPerWeek].
///
/// Two facts are stored separately, never conflated:
/// * `last_workout_date` — last civil day a workout was logged.
/// * `last_streak_day`   — last civil day the streak was kept (train or rest).
class StreakLocalDatasourceImpl implements StreakLocalDatasource {
  final SharedPreferences prefs;

  /// Injectable clock so date arithmetic is testable without touching the
  /// wall clock. Defaults to DateTime.now.
  final DateTime Function() now;

  static const _streakKey = 'streak_count';
  static const _lastWorkoutDateKey = 'last_workout_date';
  static const _lastStreakDayKey = 'last_streak_day';
  static const _restDaysRemainingKey = 'rest_days_remaining';
  static const _weekStartDateKey = 'week_start_date';
  static const _lastRestDayKey = 'last_rest_day_date';

  StreakLocalDatasourceImpl(this.prefs, {DateTime Function()? clock})
      : now = clock ?? DateTime.now;

  DateTime get _today => civilDate(now());

  DateTime? _readDate(String key) {
    final s = prefs.getString(key);
    return s == null ? null : DateTime.parse(s);
  }

  /// Installs that predate the key split wrote only `last_workout_date`
  /// (which then also meant "last streak day"). Fall back to it once; the
  /// next write populates the new key.
  DateTime? get _lastStreakDay =>
      _readDate(_lastStreakDayKey) ?? _readDate(_lastWorkoutDateKey);

  /// True when the streak is still alive as of today — i.e. today is the last
  /// streak day or the day after it.
  bool _isAlive(DateTime? lastStreakDay) =>
      lastStreakDay != null && civilDaysBetween(lastStreakDay, _today) <= 1;

  @override
  Future<int> getStreak() async {
    final count = prefs.getInt(_streakKey) ?? 0;
    // A streak with a gap > 1 day is over; report 0 rather than the stale
    // count that would otherwise persist until the next workout.
    return _isAlive(_lastStreakDay) ? count : 0;
  }

  @override
  Future<int> getRestDaysRemaining() async {
    await _initWeekIfNeeded();
    return prefs.getInt(_restDaysRemainingKey) ?? kRestDaysPerWeek;
  }

  @override
  Future<void> updateStreak() async {
    final today = _today;
    final lastWorkout = _readDate(_lastWorkoutDateKey);
    if (lastWorkout != null && isSameCivilDay(lastWorkout, today)) {
      // Second workout today: already counted.
      await _initWeekIfNeeded();
      return;
    }

    final lastStreakDay = _lastStreakDay;
    final current = prefs.getInt(_streakKey) ?? 0;
    // Alive covers both "trained yesterday" (gap 1) and "rested today, now
    // training" (gap 0) — either way today is a training day that counts.
    final next = _isAlive(lastStreakDay) ? current + 1 : 1;

    await prefs.setInt(_streakKey, next);
    await prefs.setString(_lastWorkoutDateKey, today.toIso8601String());
    await prefs.setString(_lastStreakDayKey, today.toIso8601String());
    await _initWeekIfNeeded();
  }

  @override
  Future<void> markRestDay() async {
    await _initWeekIfNeeded();
    final today = _today;

    // No streak to protect: nothing has been started, or it already lapsed.
    final lastStreakDay = _lastStreakDay;
    if ((prefs.getInt(_streakKey) ?? 0) == 0 || !_isAlive(lastStreakDay)) {
      return;
    }
    // Already trained today — a rest token would be burned for nothing.
    final lastWorkout = _readDate(_lastWorkoutDateKey);
    if (lastWorkout != null && isSameCivilDay(lastWorkout, today)) return;
    // Already rested today.
    final lastRest = _readDate(_lastRestDayKey);
    if (lastRest != null && isSameCivilDay(lastRest, today)) return;

    final remaining = prefs.getInt(_restDaysRemainingKey) ?? kRestDaysPerWeek;
    if (remaining <= 0) return;

    // Write the same-day guard *first* so a second caller interleaving at
    // any later await sees it and bails, closing the read-modify-write window.
    await prefs.setString(_lastRestDayKey, today.toIso8601String());
    await prefs.setInt(_restDaysRemainingKey, remaining - 1);
    await prefs.setString(_lastStreakDayKey, today.toIso8601String());
  }

  /// Anchors the rest-day allowance to the ISO week (Monday) containing
  /// today. Drift-free: the anchor is derived from the calendar, not from
  /// "when the app was last opened".
  Future<void> _initWeekIfNeeded() async {
    final weekStart = startOfWeek(_today);
    final stored = _readDate(_weekStartDateKey);
    if (stored != null && isSameCivilDay(stored, weekStart)) return;
    await prefs.setString(_weekStartDateKey, weekStart.toIso8601String());
    await prefs.setInt(_restDaysRemainingKey, kRestDaysPerWeek);
  }
}
