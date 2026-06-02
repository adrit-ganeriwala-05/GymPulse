import 'exercise.dart';

class Workout {
  final String id;
  final DateTime date;
  final int durationSeconds;
  final List<Exercise> exercises;

  const Workout({
    required this.id,
    required this.date,
    required this.durationSeconds,
    required this.exercises,
  });
}
