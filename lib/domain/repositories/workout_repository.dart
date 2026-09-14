import '../entities/workout.dart';
import '../entities/workout_draft.dart';

abstract class WorkoutRepository {
  /// Finished workouts only, newest first.
  Future<List<Workout>> getWorkouts();

  /// Persists a finished workout (new, or a draft being finalised).
  Future<void> saveWorkout(Workout workout);

  /// Replaces an already-finished workout in place. Same storage path as
  /// [saveWorkout]; a separate method because callers must not treat an
  /// edit as a new training event (no streak side-effect).
  Future<void> updateWorkout(Workout workout);

  /// Write-through snapshot of the in-progress session.
  Future<void> saveDraft(WorkoutDraft draft);

  Future<WorkoutDraft?> getDraft();

  Future<void> deleteWorkout(String id);

  /// Removes every in-progress draft. Home's Discard uses this rather than a
  /// delete-by-id so a stray second draft cannot survive behind the banner.
  Future<void> discardAllDrafts();

  /// Stopwatch reading for the open draft, so a resumed session continues
  /// from accumulated *active* time rather than wall-clock age.
  Future<void> recordDraftElapsed(
    String draftId,
    int elapsedSeconds, {
    required bool paused,
  });
}
