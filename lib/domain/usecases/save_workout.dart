import '../entities/workout.dart';
import '../repositories/workout_repository.dart';

class SaveWorkout {
  final WorkoutRepository repository;

  const SaveWorkout(this.repository);

  Future<void> call(Workout workout) => repository.saveWorkout(workout);
}
