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

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return openDatabase(
      path,
      version: 1,
      onConfigure: _onConfigure,
      onCreate: _createDB,
    );
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
        duration_seconds INTEGER NOT NULL DEFAULT 0
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
        weight REAL NOT NULL,
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
