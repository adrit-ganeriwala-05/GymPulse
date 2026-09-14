import '../entities/workout_draft.dart';
import '../repositories/workout_repository.dart';

class SaveDraft {
  final WorkoutRepository repository;

  const SaveDraft(this.repository);

  Future<void> call(WorkoutDraft draft) => repository.saveDraft(draft);
}
