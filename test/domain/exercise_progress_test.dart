import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/domain/read_models/exercise_progress.dart';

import '../helpers/tz.dart';

/// The PR definition and the civil-day fold, as pure rules. Each test name
/// states the rule it pins.
void main() {
  WorkoutTopSet row(DateTime date, int reps, double kg) =>
      (date: date, reps: reps, weightKg: kg);
  ExerciseProgress build(List<WorkoutTopSet> rows) =>
      ExerciseProgress.fromWorkoutTopSets(key: 'bench', displayName: 'Bench', perWorkout: rows);

  test('empty input → no days, no PR', () {
    final p = build([]);
    expect(p.isEmpty, isTrue);
    expect(p.pr, isNull);
    expect(p.prIndex, isNull);
  });

  test('a single recorded set is the PR', () {
    final p = build([row(DateTime(2025, 6, 2, 18), 5, 80)]);
    expect(p.days, hasLength(1));
    expect(p.isPr(0), isTrue);
    expect(p.matchesPr(0), isFalse);
  });

  test('PR is weight first: a heavier single beats more reps at a lower weight', () {
    final p = build([
      row(DateTime(2025, 6, 2), 10, 90),
      row(DateTime(2025, 6, 4), 1, 100),
    ]);
    expect(p.pr!.weightKg, 100);
    expect(p.pr!.reps, 1);
  });

  test('equal weight: more reps wins', () {
    final p = build([
      row(DateTime(2025, 6, 2), 5, 100),
      row(DateTime(2025, 6, 4), 8, 100),
    ]);
    expect(p.pr!.day, DateTime(2025, 6, 4));
    expect(p.pr!.reps, 8);
  });

  test('exact tie: the earliest day keeps the PR, later equal days match it', () {
    final p = build([
      row(DateTime(2025, 6, 2), 5, 100),
      row(DateTime(2025, 6, 4), 5, 100),
      row(DateTime(2025, 6, 6), 3, 100),
    ]);
    expect(p.prIndex, 0);
    expect(p.isPr(1), isFalse);
    expect(p.matchesPr(1), isTrue);
    expect(p.matchesPr(2), isFalse, reason: 'fewer reps is not a match');
  });

  test('two sessions on one civil day fold into one point keeping the stronger set', () {
    final p = build([
      row(DateTime(2025, 6, 2, 8), 5, 100),
      row(DateTime(2025, 6, 2, 18), 3, 105),
      row(DateTime(2025, 6, 3, 9), 5, 90),
    ]);
    expect(p.days.map((d) => d.day), [DateTime(2025, 6, 2), DateTime(2025, 6, 3)]);
    expect(p.days.first.weightKg, 105);
    expect(p.days, hasLength(2));
  });

  test('days are ordered oldest first regardless of input order', () {
    final p = build([
      row(DateTime(2025, 6, 4), 5, 90),
      row(DateTime(2025, 6, 2), 5, 80),
    ]);
    expect(p.days.map((d) => d.day), [DateTime(2025, 6, 2), DateTime(2025, 6, 4)]);
  });

  test('civil-day fold across the DST spring-forward pair keeps the days apart (BUG-03 class)', () {
    // 23:30 on Mar 9 and 00:30 on Mar 10 (New York) are 1 h apart across the
    // gap; a fold based on elapsed hours since a local epoch puts them in one
    // bucket. civilDate keeps them separate. Zone set here, not inherited.
    final restore = withTimeZone('America/New_York');
    addTearDown(restore);
    expect(DateTime(2025, 3, 10).difference(DateTime(2025, 3, 9)).inHours, 23,
        reason: 'the zone must really have the gap, or this test proves nothing');
    final p = build([
      row(DateTime(2025, 3, 9, 23, 30), 5, 100),
      row(DateTime(2025, 3, 10, 0, 30), 5, 100),
    ]);
    expect(p.days.map((d) => d.day), [DateTime(2025, 3, 9), DateTime(2025, 3, 10)]);
    expect(p.prIndex, 0, reason: 'earlier day keeps the PR on a tie');
    expect(p.matchesPr(1), isTrue);
  });
}
