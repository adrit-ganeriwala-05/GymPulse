import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../domain/exercise_name.dart';
import '../models/exercise_model.dart';
import '../models/workout_model.dart';
import 'workout_database.dart';

abstract class WorkoutLocalDatasource {
  /// Inserts or fully replaces the workout row and all its children.
  Future<void> upsertWorkout(
    WorkoutModel workout, {
    required String status,
    bool timerPaused = false,
  });

  /// Finished workouts only, newest first.
  Future<List<WorkoutModel>> getWorkouts();

  /// The single in-progress draft, if any, with its paused flag.
  Future<({WorkoutModel workout, bool timerPaused})?> getDraft();

  Future<void> deleteWorkout(String id);

  /// Deletes every draft row (Home's Discard). More than one should be
  /// impossible after v4's partial index; this is the belt to that brace.
  Future<void> deleteDrafts();

  /// Narrow UPDATE of the draft's stopwatch reading and paused flag.
  Future<void> updateDraftElapsed(
    String id,
    int elapsedSeconds, {
    required bool paused,
  });
}

class WorkoutLocalDatasourceImpl implements WorkoutLocalDatasource {
  static const statusDone = 'done';
  static const statusDraft = 'draft';

  Future<Database> get _db async => WorkoutDatabase.instance.database;

  @override
  Future<void> upsertWorkout(
    WorkoutModel workout, {
    required String status,
    bool timerPaused = false,
  }) async {
    final db = await _db;

    await db.transaction((txn) async {
      // Explicit DELETE then plain INSERT, not INSERT OR REPLACE. With
      // foreign_keys ON (set in onConfigure) the DELETE cascades to exercises
      // and sets, so the reinsert below cannot duplicate children. The
      // difference from OR REPLACE matters for v4's one-draft partial index:
      // OR REPLACE would satisfy that conflict by silently deleting the
      // *other* draft; a plain INSERT throws and leaves it intact (A2-08).
      await txn.delete('workouts', where: 'id = ?', whereArgs: [workout.id]);
      await txn.insert('workouts', {
        'id': workout.id,
        'date': workout.date.toIso8601String(),
        'duration_seconds': workout.durationSeconds,
        'status': status,
        'timer_paused': timerPaused ? 1 : 0,
      });

      for (int i = 0; i < workout.exerciseModels.length; i++) {
        final exercise = workout.exerciseModels[i];
        final exerciseId = const Uuid().v4();

        await txn.insert('exercises', {
          'id': exerciseId,
          'workout_id': workout.id,
          'name': exercise.name,
          'position': i,
          'name_key': normalizeExerciseName(exercise.name),
        });

        for (int j = 0; j < exercise.modelSets.length; j++) {
          final set = exercise.modelSets[j];
          await txn.insert('sets', {
            'id': const Uuid().v4(),
            'exercise_id': exerciseId,
            'reps': set.reps,
            'weight': set.weight,
            'position': j,
          });
        }
      }
    });
  }

  @override
  Future<List<WorkoutModel>> getWorkouts() async {
    final db = await _db;
    final rows = await db.query(
      'workouts',
      where: 'status = ?',
      whereArgs: [statusDone],
      orderBy: 'date DESC',
    );
    return _hydrate(db, rows);
  }

  @override
  Future<({WorkoutModel workout, bool timerPaused})?> getDraft() async {
    final db = await _db;
    final rows = await db.query(
      'workouts',
      where: 'status = ?',
      whereArgs: [statusDraft],
      orderBy: 'date DESC',
    );
    // One draft at a time is enforced by the v4 partial unique index; the
    // assert catches a future writer that bypasses it (A2-08).
    assert(rows.length <= 1, 'expected at most one draft, found ${rows.length}');
    if (rows.isEmpty) return null;
    final drafts = await _hydrate(db, rows.take(1).toList());
    return (
      workout: drafts.first,
      timerPaused: (rows.first['timer_paused'] as int? ?? 0) == 1,
    );
  }

  @override
  Future<void> deleteDrafts() async {
    final db = await _db;
    await db.delete('workouts', where: 'status = ?', whereArgs: [statusDraft]);
  }

  @override
  Future<void> updateDraftElapsed(
    String id,
    int elapsedSeconds, {
    required bool paused,
  }) async {
    final db = await _db;
    await db.update(
      'workouts',
      {'duration_seconds': elapsedSeconds, 'timer_paused': paused ? 1 : 0},
      where: 'id = ? AND status = ?',
      whereArgs: [id, statusDraft],
    );
  }

  @override
  Future<void> deleteWorkout(String id) async {
    final db = await _db;
    // Children go via ON DELETE CASCADE.
    await db.delete('workouts', where: 'id = ?', whereArgs: [id]);
  }

  // N+1 by design: one query per workout, one per exercise. At a solo
  // user's volume (a few hundred workouts, ~5 exercises each) this is a few
  // thousand cheap local reads. Revisit with a JOIN past ~2000 workouts.
  Future<List<WorkoutModel>> _hydrate(
    Database db,
    List<Map<String, Object?>> workoutMaps,
  ) async {
    final List<WorkoutModel> workouts = [];

    for (final workoutMap in workoutMaps) {
      final workoutId = workoutMap['id'] as String;

      final exerciseMaps = await db.query(
        'exercises',
        where: 'workout_id = ?',
        whereArgs: [workoutId],
        orderBy: 'position ASC',
      );

      final List<ExerciseModel> exercises = [];

      for (final exerciseMap in exerciseMaps) {
        final exerciseId = exerciseMap['id'] as String;

        final setMaps = await db.query(
          'sets',
          where: 'exercise_id = ?',
          whereArgs: [exerciseId],
          orderBy: 'position ASC',
        );

        exercises.add(ExerciseModel(
          name: exerciseMap['name'] as String,
          modelSets: setMaps
              .map((s) => ExerciseSetModel(
                    reps: s['reps'] as int,
                    weight: (s['weight'] as num).toDouble(),
                  ))
              .toList(),
        ));
      }

      workouts.add(WorkoutModel(
        id: workoutId,
        date: DateTime.parse(workoutMap['date'] as String),
        durationSeconds: workoutMap['duration_seconds'] as int,
        exerciseModels: exercises,
      ));
    }

    return workouts;
  }
}
