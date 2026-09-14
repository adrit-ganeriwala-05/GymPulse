import '../../domain/entities/workout.dart';
import 'exercise_model.dart';

class WorkoutModel extends Workout {
  final List<ExerciseModel> exerciseModels;

  WorkoutModel({
    required super.id,
    required super.date,
    required super.durationSeconds,
    required this.exerciseModels,
  }) : super(exercises: exerciseModels);

  factory WorkoutModel.fromEntity(Workout workout) => WorkoutModel(
        id: workout.id,
        date: workout.date,
        durationSeconds: workout.durationSeconds,
        exerciseModels: workout.exercises.map(ExerciseModel.fromEntity).toList(),
      );
}
