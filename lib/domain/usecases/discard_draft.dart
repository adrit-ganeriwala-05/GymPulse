import '../repositories/workout_repository.dart';

class DiscardDraft {
  final WorkoutRepository repository;

  const DiscardDraft(this.repository);

  Future<void> call(String draftId) => repository.deleteWorkout(draftId);
}
