import '../repositories/workout_repository.dart';

/// Persists the stopwatch reading for the open draft. Its own use case (not
/// folded into SaveDraft) because it must be a single-column UPDATE, not a
/// full replace of every exercise and set, and it fires on a timer.
class RecordDraftElapsed {
  final WorkoutRepository repository;

  const RecordDraftElapsed(this.repository);

  Future<void> call(String draftId, int elapsedSeconds, {required bool paused}) =>
      repository.recordDraftElapsed(draftId, elapsedSeconds, paused: paused);
}
