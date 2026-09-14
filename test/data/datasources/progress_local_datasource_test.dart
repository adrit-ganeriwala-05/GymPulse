import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/data/datasources/progress_local_datasource.dart';
import 'package:gympulse/data/datasources/workout_database.dart';
import 'package:gympulse/data/datasources/workout_local_datasource.dart';
import 'package:gympulse/data/models/exercise_model.dart';
import 'package:gympulse/data/models/workout_model.dart';
import 'package:gympulse/data/repositories/progress_repository_impl.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The aggregate query on real SQLite, through the repository so the domain
/// fold and PR rule are exercised on real rows. Includes the interaction
/// sweep: drafts, edit, delete, case variants, backdated drafts.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('gympulse-progress-').path);
  });

  late WorkoutLocalDatasourceImpl workouts;
  late ProgressRepositoryImpl progress;

  setUp(() async {
    await WorkoutDatabase.instance.close();
    await deleteDatabase(join(await getDatabasesPath(), 'gympulse.db'));
    workouts = WorkoutLocalDatasourceImpl();
    progress = ProgressRepositoryImpl(ProgressLocalDatasourceImpl());
  });

  WorkoutModel w(String id, DateTime date, String name, List<(int, double)> sets,
          {List<(String, List<(int, double)>)> more = const []}) =>
      WorkoutModel(id: id, date: date, durationSeconds: 0, exerciseModels: [
        ExerciseModel(name: name, modelSets: [for (final s in sets) ExerciseSetModel(reps: s.$1, weight: s.$2)]),
        for (final e in more)
          ExerciseModel(name: e.$1, modelSets: [for (final s in e.$2) ExerciseSetModel(reps: s.$1, weight: s.$2)]),
      ]);

  Future<void> done(WorkoutModel m) => workouts.upsertWorkout(m, status: 'done');
  Future<void> draft(WorkoutModel m) => workouts.upsertWorkout(m, status: 'draft');

  test('top set per workout: max weight, then most reps at that weight; other exercises ignored', () async {
    await done(w('a', DateTime(2025, 6, 2, 18), 'Bench', [(10, 60), (5, 100), (8, 100), (3, 90)],
        more: [('Squat', [(5, 180)])]));
    final p = await progress.getExerciseProgress('Bench');
    expect(p.days.single.weightKg, 100);
    expect(p.days.single.reps, 8, reason: 'ties on weight resolve to the most reps');
    expect(p.displayName, 'Bench');
  });

  test('an open draft with a heavier set creates no PR (status = done filter)', () async {
    await done(w('a', DateTime(2025, 6, 2), 'Bench', [(5, 100)]));
    await draft(w('d', DateTime(2025, 6, 3), 'Bench', [(1, 140)]));
    final p = await progress.getExerciseProgress('Bench');
    expect(p.days, hasLength(1));
    expect(p.pr!.weightKg, 100);
  });

  test('"Bench", "bench" and "Bench " group as one; display name is the most recent spelling', () async {
    await done(w('a', DateTime(2025, 6, 2), 'Bench', [(5, 100)]));
    await done(w('b', DateTime(2025, 6, 4), 'bench', [(5, 102.5)]));
    await done(w('c', DateTime(2025, 6, 3), 'Bench ', [(5, 101)]));
    final p = await progress.getExerciseProgress(' BENCH ');
    expect(p.key, 'bench');
    expect(p.days, hasLength(3));
    expect(p.displayName, 'bench', reason: 'workout b is the most recent');
    expect(p.pr!.weightKg, 102.5);
  });

  test('two sessions on one day → one point with the stronger set', () async {
    await done(w('am', DateTime(2025, 6, 2, 8), 'Bench', [(5, 100)]));
    await done(w('pm', DateTime(2025, 6, 2, 18), 'Bench', [(5, 105)]));
    final p = await progress.getExerciseProgress('Bench');
    expect(p.days.single.weightKg, 105);
  });

  test('weights come back in kilograms exactly as stored (conversion is the view\'s job)', () async {
    await done(w('a', DateTime(2025, 6, 2), 'Bench', [(5, 61.2349)]));
    expect((await progress.getExerciseProgress('Bench')).pr!.weightKg, 61.2349);
  });

  test('unknown exercise → empty progress, display name is the trimmed input', () async {
    final p = await progress.getExerciseProgress('  Deadlift ');
    expect(p.isEmpty, isTrue);
    expect(p.displayName, 'Deadlift');
  });

  group('interaction sweep', () {
    test('editing the workout that holds the PR set moves the PR', () async {
      await done(w('a', DateTime(2025, 6, 2), 'Bench', [(5, 100)]));
      await done(w('b', DateTime(2025, 6, 4), 'Bench', [(5, 110)]));
      expect((await progress.getExerciseProgress('Bench')).pr!.day, DateTime(2025, 6, 4));
      // Edit b: the 110 set is removed (upsert with the same id).
      await done(w('b', DateTime(2025, 6, 4), 'Bench', [(5, 95)]));
      final p = await progress.getExerciseProgress('Bench');
      expect(p.pr!.day, DateTime(2025, 6, 2));
      expect(p.days, hasLength(2), reason: 'no duplicate children after the edit');
    });

    test('deleting the workout that holds the PR recomputes it', () async {
      await done(w('a', DateTime(2025, 6, 2), 'Bench', [(5, 100)]));
      await done(w('b', DateTime(2025, 6, 4), 'Bench', [(5, 110)]));
      await workouts.deleteWorkout('b');
      final p = await progress.getExerciseProgress('Bench');
      expect(p.days, hasLength(1));
      expect(p.pr!.weightKg, 100);
    });

    test('a draft whose name differs only in case joins the series once finished', () async {
      await done(w('a', DateTime(2025, 6, 2), 'Bench', [(5, 100)]));
      await draft(w('d', DateTime(2025, 6, 3), 'bench', [(5, 120)]));
      expect((await progress.getExerciseProgress('Bench')).days, hasLength(1));
      await done(w('d', DateTime(2025, 6, 3), 'bench', [(5, 120)])); // finish
      final p = await progress.getExerciseProgress('Bench');
      expect(p.days, hasLength(2));
      expect(p.pr!.weightKg, 120);
      expect(p.displayName, 'bench');
    });

    test('a backdated finished draft lands in the middle of the history: tie keeps the earlier PR, heavier takes it', () async {
      await done(w('a', DateTime(2025, 6, 2), 'Bench', [(5, 100)]));
      await done(w('c', DateTime(2025, 6, 6), 'Bench', [(5, 100)]));
      // Started on the 4th, finished days later with the same top set.
      await draft(w('b', DateTime(2025, 6, 4), 'Bench', [(5, 100)]));
      await done(w('b', DateTime(2025, 6, 4), 'Bench', [(5, 100)]));
      var p = await progress.getExerciseProgress('Bench');
      expect(p.days.map((d) => d.day.day), [2, 4, 6]);
      expect(p.prIndex, 0);
      expect(p.matchesPr(1), isTrue);
      // Same shape, but the backdated one was heavier.
      await done(w('b', DateTime(2025, 6, 4), 'Bench', [(5, 105)]));
      p = await progress.getExerciseProgress('Bench');
      expect(p.prIndex, 1);
      expect(p.pr!.day, DateTime(2025, 6, 4));
    });

    test('a PR computed while a draft is open ignores the draft even if it is the same exercise and heavier', () async {
      await done(w('a', DateTime(2025, 6, 2), 'Bench', [(5, 100)]));
      await draft(w('d', DateTime(2025, 6, 3), 'Bench', [(5, 200)]));
      final p = await progress.getExerciseProgress('Bench');
      expect(p.pr!.weightKg, 100);
      expect(await workouts.getDraft(), isNotNull, reason: 'the draft is still there, just invisible here');
    });
  });
}
