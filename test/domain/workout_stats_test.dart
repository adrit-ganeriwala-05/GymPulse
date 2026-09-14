import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/domain/entities/exercise.dart';
import 'package:gympulse/domain/entities/workout.dart';
import 'package:gympulse/domain/workout_stats.dart';

import '../helpers/tz.dart';

Workout w(String id, DateTime date, {List<ExerciseSet> sets = const []}) =>
    Workout(id: id, date: date, durationSeconds: 0, exercises: [
      Exercise(name: 'X', sets: sets),
    ]);

void main() {
  final wed = DateTime(2025, 6, 4, 12); // Wednesday

  test('empty list → zeros and empty groupings', () {
    expect(countThisWeek([], wed), 0);
    expect(countThisMonth([], wed), 0);
    expect(longestRun([]), 0);
    expect(groupByDay([]), isEmpty);
    expect(mostRecentDay([]), isEmpty);
  });

  test('single workout', () {
    final list = [w('a', DateTime(2025, 6, 3, 9))];
    expect(countThisWeek(list, wed), 1);
    expect(countThisMonth(list, wed), 1);
    expect(longestRun(list), 1);
    expect(groupByDay(list).keys.single, DateTime(2025, 6, 3));
  });

  test('longest run: gap of exactly one day chains, gap of two breaks', () {
    final chain = [w('a', DateTime(2025, 6, 1)), w('b', DateTime(2025, 6, 2)), w('c', DateTime(2025, 6, 3))];
    expect(longestRun(chain), 3);
    final broken = [w('a', DateTime(2025, 6, 1)), w('b', DateTime(2025, 6, 3)), w('c', DateTime(2025, 6, 4))];
    expect(longestRun(broken), 2);
  });

  test('longest run survives the DST spring-forward pair (BUG-03)', () {
    final restore = withTimeZone('America/New_York');
    addTearDown(restore);
    expect(DateTime(2025, 3, 10).difference(DateTime(2025, 3, 9)).inHours, 23);
    expect(longestRun([w('a', DateTime(2025, 3, 9, 8)), w('b', DateTime(2025, 3, 10, 8))]), 2);
  });

  test('two workouts on one day count as one day everywhere', () {
    final list = [w('a', DateTime(2025, 6, 3, 8)), w('b', DateTime(2025, 6, 3, 18))];
    expect(countThisWeek(list, wed), 1);
    expect(longestRun(list), 1);
    expect(groupByDay(list)[DateTime(2025, 6, 3)], hasLength(2));
  });

  test('week is Monday-anchored: last Sunday is not this week', () {
    final list = [w('sun', DateTime(2025, 6, 1, 10)), w('mon', DateTime(2025, 6, 2, 10))];
    expect(countThisWeek(list, wed), 1);
    expect(countThisMonth(list, wed), 2);
  });

  test('mostRecentDay returns every workout on the newest day (newest-first input)', () {
    final list = [w('b', DateTime(2025, 6, 3, 18)), w('a', DateTime(2025, 6, 3, 8)), w('old', DateTime(2025, 6, 1))];
    expect(mostRecentDay(list).map((x) => x.id), ['b', 'a']);
  });

  test('totalVolumeKg sums reps × kg; empty sets → 0', () {
    expect(totalVolumeKg(w('a', wed)), 0);
    expect(totalVolumeKg(w('a', wed, sets: const [ExerciseSet(reps: 10, weight: 60), ExerciseSet(reps: 5, weight: 100)])), 1100);
  });
}
