import 'package:shared_preferences/shared_preferences.dart';

abstract class StreakLocalDatasource {
  Future<int> getStreak();
  Future<int> getRestDaysRemaining();
  Future<void> updateStreak();
  Future<void> markRestDay();
}

class StreakLocalDatasourceImpl implements StreakLocalDatasource {
  final SharedPreferences prefs;

  /// Injectable clock so date arithmetic is testable without touching the
  /// wall clock. Defaults to DateTime.now.
  final DateTime Function() now;

  static const _streakKey = 'streak_count';
  static const _lastWorkoutDateKey = 'last_workout_date';
  static const _restDaysRemainingKey = 'rest_days_remaining';
  static const _weekStartDateKey = 'week_start_date';
  static const _lastRestDayKey = 'last_rest_day_date';

  StreakLocalDatasourceImpl(this.prefs, {DateTime Function()? clock})
      : now = clock ?? DateTime.now;

  @override
  Future<int> getStreak() async => prefs.getInt(_streakKey) ?? 0;

  @override
  Future<int> getRestDaysRemaining() async {
    await _initWeekIfNeeded();
    return prefs.getInt(_restDaysRemainingKey) ?? 2;
  }

  @override
  Future<void> updateStreak() async {
    final now = this.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDateStr = prefs.getString(_lastWorkoutDateKey);
    final currentStreak = prefs.getInt(_streakKey) ?? 0;

    if (lastDateStr == null) {
      await prefs.setInt(_streakKey, 1);
      await prefs.setString(_lastWorkoutDateKey, today.toIso8601String());
      await _initWeekIfNeeded();
      return;
    }

    final lastDate = DateTime.parse(lastDateStr);
    final daysDiff = today.difference(lastDate).inDays;

    if (daysDiff == 0) {
      return;
    } else if (daysDiff == 1) {
      await prefs.setInt(_streakKey, currentStreak + 1);
    } else {
      await prefs.setInt(_streakKey, 1);
    }

    await prefs.setString(_lastWorkoutDateKey, today.toIso8601String());
    await _initWeekIfNeeded();
  }

  @override
  Future<void> markRestDay() async {
    await _initWeekIfNeeded();

    final now = this.now();
    final today = DateTime(now.year, now.month, now.day);

    // Bug 4: validate today is within the current tracked week
    final weekStartStr = prefs.getString(_weekStartDateKey);
    if (weekStartStr != null) {
      final weekStart = DateTime.parse(weekStartStr);
      final weekEnd = weekStart.add(const Duration(days: 6));
      if (today.isBefore(weekStart) || today.isAfter(weekEnd)) return;
    }

    // Bug 5: prevent marking same day twice
    final lastRestStr = prefs.getString(_lastRestDayKey);
    if (lastRestStr != null) {
      final lastRest = DateTime.parse(lastRestStr);
      if (lastRest.year == today.year &&
          lastRest.month == today.month &&
          lastRest.day == today.day) { return; }
    }

    final restDays = prefs.getInt(_restDaysRemainingKey) ?? 2;
    if (restDays > 0) {
      await prefs.setInt(_restDaysRemainingKey, restDays - 1);
      await prefs.setString(_lastRestDayKey, today.toIso8601String());
      await prefs.setString(_lastWorkoutDateKey, today.toIso8601String());
    }
  }

  Future<void> _initWeekIfNeeded() async {
    final now = this.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStartStr = prefs.getString(_weekStartDateKey);

    if (weekStartStr == null) {
      await prefs.setString(_weekStartDateKey, today.toIso8601String());
      await prefs.setInt(_restDaysRemainingKey, 2);
      return;
    }

    final weekStart = DateTime.parse(weekStartStr);
    if (today.difference(weekStart).inDays >= 7) {
      await prefs.setString(_weekStartDateKey, today.toIso8601String());
      await prefs.setInt(_restDaysRemainingKey, 2);
    }
  }
}
