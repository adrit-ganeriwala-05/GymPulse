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

  factory WorkoutModel.fromJson(Map<String, dynamic> json) => WorkoutModel(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        // FIX: null-safe cast — older stored workouts may lack this field
        durationSeconds: json['durationSeconds'] as int? ?? 0,
        exerciseModels: (json['exercises'] as List<dynamic>)
            .map((e) => ExerciseModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'durationSeconds': durationSeconds,
        'exercises': exerciseModels.map((e) => e.toJson()).toList(),
      };

  factory WorkoutModel.fromEntity(Workout workout) => WorkoutModel(
        id: workout.id,
        date: workout.date,
        durationSeconds: workout.durationSeconds,
        exerciseModels:
            workout.exercises.map(ExerciseModel.fromEntity).toList(),
      );
}
