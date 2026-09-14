import '../entities/workout.dart';
import '../repositories/workout_repository.dart';

class SaveDraft {
  final WorkoutRepository repository;

  const SaveDraft(this.repository);

  Future<void> call(Workout workout) => repository.saveDraft(workout);
}
