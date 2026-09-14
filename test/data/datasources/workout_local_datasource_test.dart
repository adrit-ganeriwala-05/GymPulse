import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/data/datasources/workout_database.dart';
import 'package:gympulse/data/datasources/workout_local_datasource.dart';
import 'package:gympulse/data/models/exercise_model.dart';
import 'package:gympulse/data/models/workout_model.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs the real datasource against real SQLite (via ffi) — no mocks — so
/// schema, pragmas and transactions are exercised, not assumed.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<String> dbPath() async =>
      join(await getDatabasesPath(), 'gympulse.db');

  setUp(() async {
    await WorkoutDatabase.instance.close();
    await deleteDatabase(await dbPath());
  });

  WorkoutModel sample({String id = 'w1', DateTime? date}) => WorkoutModel(
        id: id,
        date: date ?? DateTime(2025, 6, 2, 18),
        durationSeconds: 5400,
        exerciseModels: [
          ExerciseModel(name: 'Bench', modelSets: const [
            ExerciseSetModel(reps: 10, weight: 60),
            ExerciseSetModel(reps: 8, weight: 65),
          ]),
          ExerciseModel(name: 'Squat', modelSets: const [
            ExerciseSetModel(reps: 5, weight: 100),
          ]),
        ],
      );

  test('save then read round-trips values and preserves order', () async {
    final ds = WorkoutLocalDatasourceImpl();
    await ds.saveWorkout(sample());
    final all = await ds.getWorkouts();
    expect(all, hasLength(1));
    final w = all.single;
    expect(w.id, 'w1');
    expect(w.durationSeconds, 5400);
    expect(w.exercises.map((e) => e.name), ['Bench', 'Squat']);
    expect(w.exercises.first.sets.map((s) => s.weight), [60, 65]);
  });

  test('getWorkouts returns newest first', () async {
    final ds = WorkoutLocalDatasourceImpl();
    await ds.saveWorkout(sample(id: 'old', date: DateTime(2025, 6, 1)));
    await ds.saveWorkout(sample(id: 'new', date: DateTime(2025, 6, 3)));
    final all = await ds.getWorkouts();
    expect(all.map((w) => w.id), ['new', 'old']);
  });

  test('foreign keys are enforced: deleting a workout cascades (BUG-05)',
      () async {
    final ds = WorkoutLocalDatasourceImpl();
    await ds.saveWorkout(sample());
    final db = await WorkoutDatabase.instance.database;
    final fk = await db.rawQuery('PRAGMA foreign_keys');
    expect(fk.first.values.first, 1, reason: 'onConfigure must enable FKs');
    await db.delete('workouts', where: 'id = ?', whereArgs: ['w1']);
    expect(await db.query('exercises'), isEmpty);
    expect(await db.query('sets'), isEmpty);
  });

  test('re-saving the same id replaces children instead of duplicating',
      () async {
    final ds = WorkoutLocalDatasourceImpl();
    await ds.saveWorkout(sample());
    await ds.saveWorkout(sample());
    final db = await WorkoutDatabase.instance.database;
    expect(await db.query('exercises'), hasLength(2));
    expect(await db.query('sets'), hasLength(3));
  });

  test('concurrent first access opens the database once (BUG-12)', () async {
    final results = await Future.wait([
      WorkoutDatabase.instance.database,
      WorkoutDatabase.instance.database,
    ]);
    expect(identical(results[0], results[1]), isTrue);
  });
}
