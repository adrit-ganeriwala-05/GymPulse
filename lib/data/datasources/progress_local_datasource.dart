import 'package:sqflite/sqflite.dart';

import 'workout_database.dart';
import 'workout_local_datasource.dart';

/// One row per finished workout containing the exercise: its strongest set
/// (max weight, then max reps at that weight). Computed by SQLite, not by
/// hydrating Workout objects — this is the first read the database does the
/// work for (Feature D).
typedef TopSetRow = ({String workoutId, String date, int reps, double weight});

abstract class ProgressLocalDatasource {
  Future<List<TopSetRow>> topSetPerWorkout(String nameKey);

  /// The spelling from the most recent finished workout, or null if none.
  Future<String?> latestDisplayName(String nameKey);
}

class ProgressLocalDatasourceImpl implements ProgressLocalDatasource {
  Future<Database> get _db async => WorkoutDatabase.instance.database;

  static const _done = WorkoutLocalDatasourceImpl.statusDone;

  @override
  Future<List<TopSetRow>> topSetPerWorkout(String nameKey) async {
    final db = await _db;
    // Inner query: max weight per workout for the key (drafts excluded — the
    // status filter is not a constraint, every read repeats it). Outer query:
    // among that workout's sets at that weight, the most reps.
    final rows = await db.rawQuery('''
      SELECT w.id AS workout_id, w.date AS date, t.weight AS weight,
             MAX(s.reps) AS reps
      FROM (
        SELECT e.workout_id AS wid, MAX(s.weight) AS weight
        FROM sets s
        JOIN exercises e ON e.id = s.exercise_id
        JOIN workouts w ON w.id = e.workout_id
        WHERE w.status = ? AND e.name_key = ?
        GROUP BY e.workout_id
      ) t
      JOIN workouts w ON w.id = t.wid
      JOIN exercises e ON e.workout_id = w.id AND e.name_key = ?
      JOIN sets s ON s.exercise_id = e.id AND s.weight = t.weight
      GROUP BY w.id
      ORDER BY w.date ASC
    ''', [_done, nameKey, nameKey]);
    return rows
        .map((r) => (
              workoutId: r['workout_id'] as String,
              date: r['date'] as String,
              reps: r['reps'] as int,
              weight: (r['weight'] as num).toDouble(),
            ))
        .toList();
  }

  @override
  Future<String?> latestDisplayName(String nameKey) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT e.name AS name
      FROM exercises e
      JOIN workouts w ON w.id = e.workout_id
      WHERE w.status = ? AND e.name_key = ?
      ORDER BY w.date DESC, e.position DESC
      LIMIT 1
    ''', [_done, nameKey]);
    return rows.isEmpty ? null : rows.single['name'] as String;
  }
}
