// Pure aggregations over finished workouts. Kept out of widget build methods
// so they can be tested directly — in particular that an open draft is
// invisible to every one of them (drafts are filtered upstream by
// WorkoutRepository.getWorkouts; these functions never see status).
import 'entities/workout.dart';
import 'streak_rules.dart';

/// Workouts in the same calendar month as [now].
int countThisMonth(List<Workout> workouts, DateTime now) => workouts
    .where((w) => w.date.month == now.month && w.date.year == now.year)
    .length;

/// Distinct training *days* in the ISO week containing [now].
int countThisWeek(List<Workout> workouts, DateTime now) {
  final weekStart = startOfWeek(now);
  return workouts
      .map((w) => civilDate(w.date))
      .toSet()
      .where((d) => !d.isBefore(weekStart))
      .length;
}

/// Longest run of consecutive workout days. Cannot see rest days — hence
/// "Longest run", not "streak" (BUG-09).
int longestRun(List<Workout> workouts) {
  final days = workouts.map((w) => civilDate(w.date)).toSet().toList()..sort();
  var best = 0, cur = 0;
  DateTime? last;
  for (final day in days) {
    cur = (last != null && civilDaysBetween(last, day) == 1) ? cur + 1 : 1;
    if (cur > best) best = cur;
    last = day;
  }
  return best;
}

/// Workouts keyed by civil day (local midnight).
Map<DateTime, List<Workout>> groupByDay(List<Workout> workouts) {
  final byDay = <DateTime, List<Workout>>{};
  for (final w in workouts) {
    byDay.putIfAbsent(civilDate(w.date), () => []).add(w);
  }
  return byDay;
}

/// Every workout logged on the most recent workout day ([workouts] must be
/// newest-first, as the repository returns them).
List<Workout> mostRecentDay(List<Workout> workouts) {
  if (workouts.isEmpty) return const [];
  final latest = civilDate(workouts.first.date);
  return workouts.where((w) => civilDate(w.date) == latest).toList();
}
