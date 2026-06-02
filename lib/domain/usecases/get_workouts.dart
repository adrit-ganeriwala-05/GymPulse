import '../entities/workout.dart';
import '../repositories/workout_repository.dart';

class GetWorkouts {
  final WorkoutRepository repository;

  const GetWorkouts(this.repository);

  Future<List<Workout>> call() => repository.getWorkouts();
}
