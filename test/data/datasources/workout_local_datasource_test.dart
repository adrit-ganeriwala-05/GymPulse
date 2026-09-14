import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/data/datasources/workout_database.dart';
import 'package:gympulse/data/datasources/workout_local_datasource.dart';
import 'package:gympulse/data/models/exercise_model.dart';
import 'package:gympulse/data/models/workout_model.dart';
import 'package:gympulse/domain/workout_stats.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs the real datasource against real SQLite (via ffi) — no mocks — so
/// schema, pragmas and transactions are exercised, not assumed.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Own directory: test files run in parallel isolates (see migration_test).
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('gympulse-datasource-').path);
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
    await ds.upsertWorkout(sample(), status: 'done');
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
    await ds.upsertWorkout(sample(id: 'old', date: DateTime(2025, 6, 1)), status: 'done');
    await ds.upsertWorkout(sample(id: 'new', date: DateTime(2025, 6, 3)), status: 'done');
    final all = await ds.getWorkouts();
    expect(all.map((w) => w.id), ['new', 'old']);
  });

  test('foreign keys are enforced: deleting a workout cascades (BUG-05)',
      () async {
    final ds = WorkoutLocalDatasourceImpl();
    await ds.upsertWorkout(sample(), status: 'done');
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
    await ds.upsertWorkout(sample(), status: 'done');
    await ds.upsertWorkout(sample(), status: 'done');
    final db = await WorkoutDatabase.instance.database;
    expect(await db.query('exercises'), hasLength(2));
    expect(await db.query('sets'), hasLength(3));
  });

  test('drafts are excluded from getWorkouts and returned by getDraft', () async {
    final ds = WorkoutLocalDatasourceImpl();
    await ds.upsertWorkout(sample(id: 'd1'), status: 'draft');
    await ds.upsertWorkout(sample(id: 'w1'), status: 'done');
    expect((await ds.getWorkouts()).map((w) => w.id), ['w1']);
    expect((await ds.getDraft())?.workout.id, 'd1');
  });

  test('an open draft is invisible to every aggregate', () async {
    final ds = WorkoutLocalDatasourceImpl();
    final now = DateTime(2025, 6, 4, 12); // Wednesday
    await ds.upsertWorkout(sample(id: 'done', date: DateTime(2025, 6, 3, 9)), status: 'done');
    await ds.upsertWorkout(
      WorkoutModel(id: 'draft', date: now, durationSeconds: 0, exerciseModels: const []),
      status: 'draft',
    );
    final visible = await ds.getWorkouts();
    expect(visible.map((w) => w.id), ['done']);
    expect(countThisWeek(visible, now), 1);
    expect(countThisMonth(visible, now), 1);
    expect(longestRun(visible), 1);
    expect(groupByDay(visible).containsKey(DateTime(2025, 6, 4)), isFalse,
        reason: 'no phantom zero-exercise day on the calendar');
    expect(mostRecentDay(visible).single.id, 'done');
  });

  test('updateDraftElapsed touches only the draft duration + paused flag', () async {
    final ds = WorkoutLocalDatasourceImpl();
    await ds.upsertWorkout(sample(id: 'd'), status: 'draft');
    await ds.updateDraftElapsed('d', 754, paused: true);
    final d = (await ds.getDraft())!;
    expect(d.workout.durationSeconds, 754);
    expect(d.timerPaused, isTrue);
    expect(d.workout.exercises, hasLength(2), reason: 'children untouched');
    await ds.upsertWorkout(sample(id: 'd'), status: 'done');
    await ds.updateDraftElapsed('d', 999, paused: false); // not a draft: no-op
    expect((await ds.getWorkouts()).single.durationSeconds, 5400);
  });

  test('paused flag round-trips through the full draft snapshot', () async {
    final ds = WorkoutLocalDatasourceImpl();
    await ds.upsertWorkout(sample(id: 'd'), status: 'draft', timerPaused: true);
    expect((await ds.getDraft())!.timerPaused, isTrue);
    await ds.upsertWorkout(sample(id: 'd'), status: 'draft');
    expect((await ds.getDraft())!.timerPaused, isFalse);
  });

  test('finishing a draft flips it in place: no second row', () async {
    final ds = WorkoutLocalDatasourceImpl();
    await ds.upsertWorkout(sample(id: 'd1'), status: 'draft');
    await ds.upsertWorkout(sample(id: 'd1'), status: 'done');
    expect(await ds.getDraft(), isNull);
    expect((await ds.getWorkouts()).map((w) => w.id), ['d1']);
    final db = await WorkoutDatabase.instance.database;
    expect(await db.query('workouts'), hasLength(1));
  });

  test('a second draft cannot be inserted: the partial index throws and the first is intact (A2-08)', () async {
    final ds = WorkoutLocalDatasourceImpl();
    await ds.upsertWorkout(sample(id: 'd1'), status: 'draft');
    await expectLater(
      ds.upsertWorkout(sample(id: 'd2', date: DateTime(2025, 6, 9)), status: 'draft'),
      throwsA(isA<DatabaseException>()),
    );
    final d = (await ds.getDraft())!;
    expect(d.workout.id, 'd1');
    expect(d.workout.exercises, hasLength(2), reason: 'a plain INSERT conflict does not touch the other draft');
    // Re-saving the *same* draft still works (DELETE then INSERT by id).
    await ds.upsertWorkout(sample(id: 'd1'), status: 'draft', timerPaused: true);
    expect((await ds.getDraft())!.timerPaused, isTrue);
  });

  test('exercises are stored with a normalised name_key', () async {
    final ds = WorkoutLocalDatasourceImpl();
    await ds.upsertWorkout(
      WorkoutModel(id: 'w', date: DateTime(2025, 6, 2), durationSeconds: 0, exerciseModels: [
        ExerciseModel(name: ' Bench Press ', modelSets: const []),
      ]),
      status: 'done',
    );
    final db = await WorkoutDatabase.instance.database;
    expect((await db.query('exercises')).single['name_key'], 'bench press');
  });

  test('deleteDrafts removes every draft row and no finished one (A2-08)', () async {
    final ds = WorkoutLocalDatasourceImpl();
    await ds.upsertWorkout(sample(id: 'done'), status: 'done');
    await ds.upsertWorkout(sample(id: 'd1', date: DateTime(2025, 6, 5)), status: 'draft');
    await ds.deleteDrafts();
    expect(await ds.getDraft(), isNull);
    expect((await ds.getWorkouts()).single.id, 'done');
    final db = await WorkoutDatabase.instance.database;
    expect(await db.query('exercises'), hasLength(2), reason: 'only the draft\'s children went');
  });

  test('deleteWorkout cascades to exercises and sets', () async {
    final ds = WorkoutLocalDatasourceImpl();
    await ds.upsertWorkout(sample(), status: 'done');
    await ds.deleteWorkout('w1');
    final db = await WorkoutDatabase.instance.database;
    expect(await db.query('exercises'), isEmpty);
    expect(await db.query('sets'), isEmpty);
  });

  test('v1 database migrates to v2 with existing workouts intact', () async {
    // Build a v1 file exactly as the pre-change schema did (no status col).
    final path = await dbPath();
    final v1 = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('CREATE TABLE workouts (id TEXT PRIMARY KEY, date TEXT NOT NULL, duration_seconds INTEGER NOT NULL DEFAULT 0)');
      await db.execute('CREATE TABLE exercises (id TEXT PRIMARY KEY, workout_id TEXT NOT NULL, name TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (workout_id) REFERENCES workouts(id) ON DELETE CASCADE)');
      await db.execute('CREATE TABLE sets (id TEXT PRIMARY KEY, exercise_id TEXT NOT NULL, reps INTEGER NOT NULL, weight REAL NOT NULL, position INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE)');
    });
    await v1.insert('workouts', {'id': 'legacy', 'date': '2025-01-05T10:00:00.000', 'duration_seconds': 1200});
    await v1.insert('exercises', {'id': 'e1', 'workout_id': 'legacy', 'name': 'Row', 'position': 0});
    await v1.insert('sets', {'id': 's1', 'exercise_id': 'e1', 'reps': 12, 'weight': 40.0, 'position': 0});
    expect(await v1.getVersion(), 1);
    await v1.close();

    // Opening through the app's WorkoutDatabase runs _onUpgrade.
    final db = await WorkoutDatabase.instance.database;
    expect(await db.getVersion(), WorkoutDatabase.schemaVersion);
    final cols = (await db.rawQuery('PRAGMA table_info(workouts)'))
        .map((r) => r['name'])
        .toSet();
    expect(cols, containsAll(['status', 'timer_paused']),
        reason: 'both ladder steps applied in order');
    final all = await WorkoutLocalDatasourceImpl().getWorkouts();
    expect(all.map((w) => w.id), ['legacy']);
    expect(all.single.exercises.single.sets.single.weight, 40.0);
    expect(await WorkoutLocalDatasourceImpl().getDraft(), isNull);
  });

  test('v2 database (status column, open draft) migrates to v3 without re-running the v2 step', () async {
    // The v1→v3 test above cannot catch a ladder that re-applies step 2 on a
    // v2 file ("duplicate column name: status"). Build a real v2 file.
    final path = await dbPath();
    final v2 = await openDatabase(path, version: 2, onCreate: (db, _) async {
      await db.execute("CREATE TABLE workouts (id TEXT PRIMARY KEY, date TEXT NOT NULL, duration_seconds INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'done')");
      await db.execute('CREATE TABLE exercises (id TEXT PRIMARY KEY, workout_id TEXT NOT NULL, name TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (workout_id) REFERENCES workouts(id) ON DELETE CASCADE)');
      await db.execute('CREATE TABLE sets (id TEXT PRIMARY KEY, exercise_id TEXT NOT NULL, reps INTEGER NOT NULL, weight REAL NOT NULL, position INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE)');
    });
    await v2.insert('workouts', {'id': 'done1', 'date': '2025-01-05T10:00:00.000', 'duration_seconds': 1200, 'status': 'done'});
    await v2.insert('workouts', {'id': 'draft1', 'date': '2025-01-06T10:00:00.000', 'duration_seconds': 300, 'status': 'draft'});
    await v2.insert('exercises', {'id': 'e1', 'workout_id': 'draft1', 'name': 'Row', 'position': 0});
    await v2.close();

    final db = await WorkoutDatabase.instance.database;
    expect(await db.getVersion(), WorkoutDatabase.schemaVersion);
    final ds = WorkoutLocalDatasourceImpl();
    expect((await ds.getWorkouts()).map((w) => w.id), ['done1']);
    final d = (await ds.getDraft())!;
    expect(d.workout.id, 'draft1');
    expect(d.timerPaused, isFalse, reason: 'v3 default backfills 0');
    expect(d.workout.exercises.single.name, 'Row');
  });

  test('a failed open is not cached: the next caller retries (BUG-12 guard)', () async {
    // sqflite already single-instances and serialises openDatabase per path,
    // so "opens once" is not observable; the reset-on-failure branch is.
    final good = await getDatabasesPath();
    // Root-owned parent: neither the directory nor the file can be created.
    await databaseFactory.setDatabasesPath('/gympulse-audit2-no-such-dir/db');
    addTearDown(() => databaseFactory.setDatabasesPath(good));
    await expectLater(WorkoutDatabase.instance.database, throwsA(anything));
    await databaseFactory.setDatabasesPath(good);
    final db = await WorkoutDatabase.instance.database;
    expect(await db.getVersion(), WorkoutDatabase.schemaVersion);
  });
}
