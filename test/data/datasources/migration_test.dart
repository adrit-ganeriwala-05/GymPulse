import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/data/datasources/workout_database.dart';
import 'package:gympulse/data/datasources/workout_local_datasource.dart';
import 'package:gympulse/domain/exercise_name.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Every hop of the ladder on a hand-built file *at that version*, plus the
/// full chain through the app's own opener. A suite that only walks v1 -> N
/// stays green while a middle step rots (e.g. a step re-applied on a file
/// that already has its column).
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Test files run in parallel isolates; give this one its own directory so
    // it never shares gympulse.db with another file's tests.
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('gympulse-migration-').path);
  });

  late String path;
  setUp(() async {
    await WorkoutDatabase.instance.close();
    path = join(await getDatabasesPath(), 'gympulse.db');
    await deleteDatabase(path);
  });

  // Historical DDL, verbatim from each version's _createDB.
  const workoutsV1 =
      'CREATE TABLE workouts (id TEXT PRIMARY KEY, date TEXT NOT NULL, duration_seconds INTEGER NOT NULL DEFAULT 0)';
  const workoutsV2 =
      "CREATE TABLE workouts (id TEXT PRIMARY KEY, date TEXT NOT NULL, duration_seconds INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'done')";
  const workoutsV3 =
      "CREATE TABLE workouts (id TEXT PRIMARY KEY, date TEXT NOT NULL, duration_seconds INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'done', timer_paused INTEGER NOT NULL DEFAULT 0)";
  const exercisesPreV4 =
      'CREATE TABLE exercises (id TEXT PRIMARY KEY, workout_id TEXT NOT NULL, name TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (workout_id) REFERENCES workouts(id) ON DELETE CASCADE)';
  const setsPreV4 =
      'CREATE TABLE sets (id TEXT PRIMARY KEY, exercise_id TEXT NOT NULL, reps INTEGER NOT NULL, weight REAL NOT NULL, position INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE)';

  Future<Database> buildAt(int version, String workoutsDdl) =>
      openDatabase(path, version: version, onCreate: (db, _) async {
        await db.execute(workoutsDdl);
        await db.execute(exercisesPreV4);
        await db.execute(setsPreV4);
      });

  /// A finished workout with one exercise/set; from v2 on, a draft too, with
  /// name variants that the v4 key must fold.
  Future<void> seed(Database db, {required int version}) async {
    await db.insert('workouts', {
      'id': 'legacy',
      'date': '2025-01-05T10:00:00.000',
      'duration_seconds': 1200,
      if (version >= 2) 'status': 'done',
    });
    await db.insert('exercises', {'id': 'e1', 'workout_id': 'legacy', 'name': 'Legacy Row', 'position': 0});
    await db.insert('sets', {'id': 's1', 'exercise_id': 'e1', 'reps': 12, 'weight': 40.0, 'position': 0});
    if (version >= 2) {
      await db.insert('workouts', {
        'id': 'draft1',
        'date': '2025-01-06T10:00:00.000',
        'duration_seconds': 300,
        'status': 'draft',
        if (version >= 3) 'timer_paused': 1,
      });
      await db.insert('exercises', {'id': 'e2', 'workout_id': 'draft1', 'name': ' Bench ', 'position': 0});
      await db.insert('exercises', {'id': 'e3', 'workout_id': 'draft1', 'name': 'Über Row', 'position': 1});
      await db.insert('sets', {'id': 's2', 'exercise_id': 'e2', 'reps': 5, 'weight': 100.0, 'position': 0});
    }
  }

  Future<Database> hop(int to) => openDatabase(
        path,
        version: to,
        onConfigure: WorkoutDatabase.configure,
        onUpgrade: WorkoutDatabase.migrate,
      );

  Future<Set<String>> cols(Database db, String table) async =>
      (await db.rawQuery('PRAGMA table_info($table)')).map((r) => r['name'] as String).toSet();

  Future<String> ddl(Database db, String name) async =>
      (await db.rawQuery("SELECT sql FROM sqlite_master WHERE name = ?", [name])).single['sql'] as String;

  test('v1 -> v2: status column added with done backfill, rows intact', () async {
    final v1 = await buildAt(1, workoutsV1);
    await seed(v1, version: 1);
    await v1.close();
    final db = await hop(2);
    expect(await db.getVersion(), 2);
    expect(await cols(db, 'workouts'), {'id', 'date', 'duration_seconds', 'status'});
    expect((await db.query('workouts')).single['status'], 'done');
    expect(await db.query('sets'), hasLength(1));
    await db.close();
  });

  test('v2 -> v3: timer_paused added; the v2 step is not re-applied to a file that has status', () async {
    final v2 = await buildAt(2, workoutsV2);
    await seed(v2, version: 2);
    await v2.close();
    final db = await hop(3);
    expect(await db.getVersion(), 3);
    expect(await cols(db, 'workouts'), {'id', 'date', 'duration_seconds', 'status', 'timer_paused'});
    final draft = (await db.query('workouts', where: "status = 'draft'")).single;
    expect(draft['timer_paused'], 0, reason: 'v3 default backfills 0');
    expect(await db.query('exercises'), hasLength(3));
    await db.close();
  });

  test('v3 -> v4: rebuild keeps every row and child, adds CHECK, one-draft index and name_key; FKs still cascade', () async {
    final v3 = await buildAt(3, workoutsV3);
    await seed(v3, version: 3);
    await v3.close();
    final db = await hop(4);
    expect(await db.getVersion(), 4);

    // Shape.
    expect(await cols(db, 'workouts'), {'id', 'date', 'duration_seconds', 'status', 'timer_paused'});
    expect(await cols(db, 'exercises'), {'id', 'workout_id', 'name', 'position', 'name_key'});
    expect(await ddl(db, 'workouts'), contains('CHECK'));
    expect(await ddl(db, 'one_draft'), contains("WHERE status = 'draft'"));
    expect((await db.rawQuery('PRAGMA foreign_key_list(exercises)')).single['table'], 'workouts',
        reason: 'the rebuilt child references the rebuilt parent, not a *_old table');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect((await db.rawQuery("SELECT name FROM sqlite_master WHERE name LIKE '%_old'")), isEmpty);

    // Rows and children survived; draft flag and status preserved.
    expect(await db.query('workouts'), hasLength(2));
    expect(await db.query('exercises'), hasLength(3));
    expect(await db.query('sets'), hasLength(2));
    final draft = (await db.query('workouts', where: "status = 'draft'")).single;
    expect(draft['timer_paused'], 1);

    // name_key backfilled with the Dart rule (Unicode fold, trim).
    final keys = {for (final r in await db.query('exercises')) r['name'] as String: r['name_key'] as String};
    expect(keys, {'Legacy Row': 'legacy row', ' Bench ': 'bench', 'Über Row': 'über row'});
    for (final e in keys.entries) {
      expect(e.value, normalizeExerciseName(e.key));
    }

    // Constraints are live.
    await expectLater(
      db.insert('workouts', {'id': 'draft2', 'date': '2025-01-07T10:00:00.000', 'duration_seconds': 0, 'status': 'draft'}),
      throwsA(isA<DatabaseException>()),
      reason: 'one draft at a time',
    );
    await expectLater(
      db.insert('workouts', {'id': 'x', 'date': '2025-01-07T10:00:00.000', 'duration_seconds': 0, 'status': 'bogus'}),
      throwsA(isA<DatabaseException>()),
      reason: 'CHECK on status',
    );

    // Cascade still wired after the rebuild.
    await db.delete('workouts', where: "id = 'draft1'");
    expect(await db.query('exercises', where: "workout_id = 'draft1'"), isEmpty);
    expect(await db.query('sets', where: "id = 's2'"), isEmpty);
    await db.close();
  });

  test('v3 -> v4 with two pre-existing drafts keeps the newest (the one LIMIT 1 showed)', () async {
    final v3 = await buildAt(3, workoutsV3);
    await seed(v3, version: 3);
    await v3.insert('workouts', {'id': 'older-draft', 'date': '2024-12-31T10:00:00.000', 'duration_seconds': 10, 'status': 'draft'});
    await v3.insert('exercises', {'id': 'e9', 'workout_id': 'older-draft', 'name': 'Ghost', 'position': 0});
    await v3.close();
    final db = await hop(4);
    final drafts = await db.query('workouts', where: "status = 'draft'");
    expect(drafts.map((r) => r['id']), ['draft1']);
    expect(await db.query('exercises', where: "workout_id = 'older-draft'"), isEmpty,
        reason: 'the hidden draft and its children are gone, not orphaned');
    await db.close();
  });

  test('v1 -> v4 through the app opener produces the same shape as a fresh v4', () async {
    final v1 = await buildAt(1, workoutsV1);
    await seed(v1, version: 1);
    await v1.close();

    Future<Map<String, Object?>> shape(Database db) async => {
          for (final t in ['workouts', 'exercises', 'sets'])
            t: (await db.rawQuery('PRAGMA table_info($t)'))
                .map((r) => '${r['name']}:${r['type']}:${r['notnull']}:${r['dflt_value']}:${r['pk']}')
                .toList(),
          'indexes': (await db.rawQuery("SELECT name, sql FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL ORDER BY name"))
              .map((r) => '${r['name']}|${r['sql']}')
              .toList(),
          'checks': (await ddl(db, 'workouts')).contains('CHECK'),
        };

    final migrated = await WorkoutDatabase.instance.database;
    expect(await migrated.getVersion(), 4);
    final migratedShape = await shape(migrated);
    final legacy = (await WorkoutLocalDatasourceImpl().getWorkouts()).single;
    expect(legacy.exercises.single.sets.single.weight, 40.0);
    expect((await migrated.query('exercises')).single['name_key'], 'legacy row');
    await WorkoutDatabase.instance.close();

    await deleteDatabase(path);
    final fresh = await WorkoutDatabase.instance.database;
    expect(await shape(fresh), migratedShape, reason: '_createDB and the ladder must not drift');
  });
}
