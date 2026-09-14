import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../../domain/exercise_name.dart';

class WorkoutDatabase {
  static final WorkoutDatabase instance = WorkoutDatabase._init();

  // Cache the *future*, not the resolved value. `??=` assigns synchronously
  // before any await can interleave, so concurrent first callers share one
  // in-flight open instead of each calling openDatabase (BUG-12).
  static Future<Database>? _databaseFuture;

  WorkoutDatabase._init();

  Future<Database> get database => _databaseFuture ??= _initDB('gympulse.db')
      .catchError((Object e, StackTrace s) {
        // Don't cache a failed open; let the next caller retry.
        _databaseFuture = null;
        throw e;
      });

  /// Bump this when the schema changes and add a step to [migrate].
  /// [_createDB] must produce the same shape a fully-migrated DB has; the v4
  /// step reuses its DDL so the two cannot drift.
  static const schemaVersion = 4;

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: configure,
      onCreate: _createDB,
      onUpgrade: migrate,
      // Single-user, local-only, no sync: an app downgrade wiping the DB is
      // preferable to an unlaunchable app. Approved in the Phase 2 brief.
      onDowngrade: onDatabaseDowngradeDelete,
    );
  }

  /// Forward-only migration ladder: step N runs iff `old < N <= new`, so a
  /// user jumping v1 -> v4 applies every intermediate step in order, and a
  /// test can drive exactly one hop on a hand-built file. sqflite runs this
  /// inside a transaction, so a failing step rolls back atomically.
  static Future<void> migrate(Database db, int oldVersion, int newVersion) async {
    bool step(int n) => oldVersion < n && newVersion >= n;
    if (step(2)) {
      // v2: in-progress drafts live in the same table. Every pre-existing
      // row is a finished workout, so the default backfills correctly.
      await db.execute(
        "ALTER TABLE workouts ADD COLUMN status TEXT NOT NULL DEFAULT 'done'",
      );
    }
    if (step(3)) {
      // v3: was the draft's stopwatch paused at the last checkpoint?
      await db.execute(
        'ALTER TABLE workouts ADD COLUMN timer_paused INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (step(4)) {
      await _upgradeToV4(db);
    }
  }

  /// v4 (A2-08 + Feature D): CHECK on `status`, one-draft partial unique
  /// index, `exercises.name_key` (normalised name) with an index.
  ///
  /// A CHECK needs a table rebuild. `DROP TABLE` on a parent with foreign
  /// keys ON performs an implicit DELETE that *cascades into the children*,
  /// and `PRAGMA foreign_keys = OFF` is a no-op inside the upgrade
  /// transaction — so the rebuild renames the old tables away, creates the
  /// new ones with the very DDL [_createDB] uses, copies, and only then drops
  /// the old set (children first, so no cascade ever fires).
  static Future<void> _upgradeToV4(Database db) async {
    await db.execute('ALTER TABLE workouts RENAME TO workouts_old');
    await db.execute('ALTER TABLE exercises RENAME TO exercises_old');
    await db.execute('ALTER TABLE sets RENAME TO sets_old');

    await _createTables(db);

    // Pre-v4 code could, on a failed draft read, leave a second draft row
    // that LIMIT 1 then hid forever. Keep the newest (the one the user could
    // see) so the partial unique index can be created.
    await db.execute("""
      DELETE FROM workouts_old
      WHERE status = 'draft' AND id NOT IN (
        SELECT id FROM workouts_old WHERE status = 'draft'
        ORDER BY date DESC LIMIT 1
      )
    """);

    await db.execute('''
      INSERT INTO workouts (id, date, duration_seconds, status, timer_paused)
      SELECT id, date, duration_seconds, status, timer_paused FROM workouts_old
    ''');
    await db.execute("""
      INSERT INTO exercises (id, workout_id, name, position, name_key)
      SELECT id, workout_id, name, position, '' FROM exercises_old
    """);
    await db.execute('''
      INSERT INTO sets (id, exercise_id, reps, weight, position)
      SELECT id, exercise_id, reps, weight, position FROM sets_old
    ''');

    await db.execute('DROP TABLE sets_old');
    await db.execute('DROP TABLE exercises_old');
    await db.execute('DROP TABLE workouts_old');

    // Backfill the key from Dart, not SQL: SQLite's lower() is ASCII-only and
    // the app writes Unicode-folded keys — the two must never disagree.
    final rows = await db.query('exercises', columns: ['id', 'name']);
    for (final r in rows) {
      await db.update(
        'exercises',
        {'name_key': normalizeExerciseName(r['name'] as String)},
        where: 'id = ?',
        whereArgs: [r['id']],
      );
    }

    await _createIndexes(db);
  }

  // onConfigure runs on every open, before onCreate/onUpgrade, and outside
  // their transaction. PRAGMA foreign_keys is a silent no-op inside a
  // transaction, so this is the only hook where it reliably takes effect
  // (BUG-05) — including during migrations. Public for the hop tests.
  static Future<void> configure(Database db) =>
      db.execute('PRAGMA foreign_keys = ON');

  static Future<void> _createDB(Database db, int version) async {
    await _createTables(db);
    await _createIndexes(db);
  }

  /// The one definition of the table shape; both a fresh install and the v4
  /// rebuild run exactly this.
  static Future<void> _createTables(Database db) async {
    await db.execute("""
      CREATE TABLE workouts (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'done'
          CHECK (status IN ('done', 'draft')),  -- v2 column, v4 CHECK
        timer_paused INTEGER NOT NULL DEFAULT 0  -- draft stopwatch paused (v3)
      )
    """);

    await db.execute('''
      CREATE TABLE exercises (
        id TEXT PRIMARY KEY,
        workout_id TEXT NOT NULL,
        name TEXT NOT NULL,
        position INTEGER NOT NULL DEFAULT 0,
        name_key TEXT NOT NULL,      -- normalizeExerciseName(name) (v4)
        FOREIGN KEY (workout_id)
          REFERENCES workouts(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE sets (
        id TEXT PRIMARY KEY,
        exercise_id TEXT NOT NULL,
        reps INTEGER NOT NULL,
        weight REAL NOT NULL,        -- kilograms, always (see BUG-01)
        position INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (exercise_id)
          REFERENCES exercises(id)
          ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _createIndexes(Database db) async {
    // One draft at a time (A2-08). A second draft INSERT throws rather than
    // silently hiding behind LIMIT 1.
    await db.execute("""
      CREATE UNIQUE INDEX one_draft ON workouts(status) WHERE status = 'draft'
    """);
    // Feature D groups by the normalised name.
    await db.execute('CREATE INDEX exercises_name_key ON exercises(name_key)');
  }

  Future<void> close() async {
    final pending = _databaseFuture;
    if (pending == null) return;
    _databaseFuture = null;
    final db = await pending;
    await db.close();
  }
}
