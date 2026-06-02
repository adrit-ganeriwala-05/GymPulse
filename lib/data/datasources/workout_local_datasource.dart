import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/exercise_model.dart';
import '../models/workout_model.dart';
import 'workout_database.dart';

abstract class WorkoutLocalDatasource {
  Future<void> saveWorkout(WorkoutModel workout);
  Future<List<WorkoutModel>> getWorkouts();
}

class WorkoutLocalDatasourceImpl implements WorkoutLocalDatasource {
  Future<Database> get _db async => WorkoutDatabase.instance.database;

  @override
  Future<void> saveWorkout(WorkoutModel workout) async {
    final db = await _db;

    await db.transaction((txn) async {
      await txn.insert(
        'workouts',
        {
          'id': workout.id,
          'date': workout.date.toIso8601String(),
          'duration_seconds': workout.durationSeconds,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (int i = 0; i < workout.exerciseModels.length; i++) {
        final exercise = workout.exerciseModels[i];
        final exerciseId = const Uuid().v4();

        await txn.insert('exercises', {
          'id': exerciseId,
          'workout_id': workout.id,
          'name': exercise.name,
          'position': i,
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

    final workoutMaps = await db.query('workouts', orderBy: 'date DESC');
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

        final sets = setMaps
            .map((s) => ExerciseSetModel(
                  reps: s['reps'] as int,
                  weight: (s['weight'] as num).toDouble(),
                ))
            .toList();

        exercises.add(ExerciseModel(
          name: exerciseMap['name'] as String,
          modelSets: sets,
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
