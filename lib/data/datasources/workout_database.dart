import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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

  /// Bump this when the schema changes and add a step to [_onUpgrade].
  /// [_createDB] must produce the same shape a fully-migrated DB has.
  static const schemaVersion = 2;

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: _onConfigure,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
      // Single-user, local-only, no sync: an app downgrade wiping the DB is
      // preferable to an unlaunchable app. Approved in the Phase 2 brief.
      onDowngrade: onDatabaseDowngradeDelete,
    );
  }

  /// Forward-only migration ladder. `if (oldVersion < N)` (not a switch) so a
  /// user jumping v1 -> v4 applies every intermediate step in order. sqflite
  /// runs this inside a transaction, so a failing step rolls back atomically.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v2: in-progress drafts live in the same table. Every pre-existing
      // row is a finished workout, so the default backfills correctly.
      await db.execute(
        "ALTER TABLE workouts ADD COLUMN status TEXT NOT NULL DEFAULT 'done'",
      );
    }
  }

  // onConfigure runs on every open, before onCreate/onUpgrade, and outside
  // their transaction. PRAGMA foreign_keys is a silent no-op inside a
  // transaction, so this is the only hook where it reliably takes effect
  // (BUG-05) — including during future migrations.
  Future<void> _onConfigure(Database db) =>
      db.execute('PRAGMA foreign_keys = ON');

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE workouts (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'done'   -- 'done' | 'draft' (v2)
      )
    ''');

    await db.execute('''
      CREATE TABLE exercises (
        id TEXT PRIMARY KEY,
        workout_id TEXT NOT NULL,
        name TEXT NOT NULL,
        position INTEGER NOT NULL DEFAULT 0,
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

  Future<void> close() async {
    final pending = _databaseFuture;
    if (pending == null) return;
    _databaseFuture = null;
    final db = await pending;
    await db.close();
  }
}
