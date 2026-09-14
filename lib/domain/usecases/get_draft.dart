import '../entities/workout_draft.dart';
import '../repositories/workout_repository.dart';

class GetDraft {
  final WorkoutRepository repository;

  const GetDraft(this.repository);

  Future<WorkoutDraft?> call() => repository.getDraft();
}
