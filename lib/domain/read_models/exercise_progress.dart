// A read model, not an entity. "Top set per training day for one exercise"
// maps to no aggregate root: it is a projection SQLite computes across many
// workouts and the app never writes back. It lives in domain (so presentation
// need not import data) but under read_models/, not entities/, to signal
// derived, read-only, query-shaped. See WALKTHROUGH.md.
import '../streak_rules.dart';

/// The strongest set of one exercise on one civil day.
class ExerciseTopSet {
  /// Local civil day (midnight), via [civilDate] — never wall-clock math.
  final DateTime day;
  final int reps;

  /// Kilograms, always; presentation converts (see units.dart).
  final double weightKg;

  const ExerciseTopSet({
    required this.day,
    required this.reps,
    required this.weightKg,
  });

  /// Strength ordering used for both "top set of the day" and "PR":
  /// weight first, then reps. A heavier single beats more reps at a lower
  /// weight; equal weight and reps tie.
  int compareStrength(ExerciseTopSet other) {
    final w = weightKg.compareTo(other.weightKg);
    return w != 0 ? w : reps.compareTo(other.reps);
  }
}

/// One row of the aggregate as the datasource returns it: the top set of the
/// exercise within one *workout*. The fold into civil days happens here, in
/// domain, so the day rule is the app's DST-safe one and not SQLite's.
typedef WorkoutTopSet = ({DateTime date, int reps, double weightKg});

class ExerciseProgress {
  /// Normalised key (see normalizeExerciseName).
  final String key;

  /// The spelling shown in the UI: the most recent one the user typed.
  final String displayName;

  /// Oldest first, exactly one per civil day.
  final List<ExerciseTopSet> days;

  /// Index into [days] of the PR: the *earliest* day on which the all-time
  /// best (weight, reps) was achieved. Later equal days match it, they do not
  /// take it over. Null when [days] is empty.
  final int? prIndex;

  const ExerciseProgress({
    required this.key,
    required this.displayName,
    required this.days,
    required this.prIndex,
  });

  bool get isEmpty => days.isEmpty;
  ExerciseTopSet? get pr => prIndex == null ? null : days[prIndex!];
  bool isPr(int i) => i == prIndex;
  bool matchesPr(int i) =>
      prIndex != null && i != prIndex && days[i].compareStrength(pr!) == 0;

  /// Folds per-workout top sets into per-day top sets (two sessions on one
  /// day keep the stronger) and picks the PR under [compareStrength].
  factory ExerciseProgress.fromWorkoutTopSets({
    required String key,
    required String displayName,
    required Iterable<WorkoutTopSet> perWorkout,
  }) {
    final byDay = <DateTime, ExerciseTopSet>{};
    for (final r in perWorkout) {
      final day = civilDate(r.date);
      final candidate =
          ExerciseTopSet(day: day, reps: r.reps, weightKg: r.weightKg);
      final existing = byDay[day];
      if (existing == null || candidate.compareStrength(existing) > 0) {
        byDay[day] = candidate;
      }
    }
    final days = byDay.values.toList()..sort((a, b) => a.day.compareTo(b.day));
    int? prIndex;
    for (var i = 0; i < days.length; i++) {
      // Strictly greater: on a tie the earlier day keeps the PR.
      if (prIndex == null || days[i].compareStrength(days[prIndex]) > 0) {
        prIndex = i;
      }
    }
    return ExerciseProgress(
      key: key,
      displayName: displayName,
      days: days,
      prIndex: prIndex,
    );
  }
}
