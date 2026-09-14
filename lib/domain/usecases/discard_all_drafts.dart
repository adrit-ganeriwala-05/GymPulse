import '../repositories/workout_repository.dart';

/// Home's Discard. Deletes every draft row, not only the one the banner shows,
/// so a hidden second draft cannot outlive the user's decision (A2-08).
class DiscardAllDrafts {
  final WorkoutRepository repository;

  const DiscardAllDrafts(this.repository);

  Future<void> call() => repository.discardAllDrafts();
}
