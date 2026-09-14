import '../entities/workout.dart';
import '../repositories/workout_repository.dart';

class UpdateWorkout {
  final WorkoutRepository repository;

  const UpdateWorkout(this.repository);

  Future<void> call(Workout workout) => repository.updateWorkout(workout);
}
