import '../repositories/workout_repository.dart';

class DeleteWorkout {
  final WorkoutRepository repository;

  const DeleteWorkout(this.repository);

  Future<void> call(String id) => repository.deleteWorkout(id);
}
