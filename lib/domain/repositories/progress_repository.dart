import '../read_models/exercise_progress.dart';

/// Read-only. Separate from WorkoutRepository because the shape it returns is
/// a query result over many workouts, not an aggregate root; keeping it apart
/// stops the workout repository from growing report methods.
abstract class ProgressRepository {
  /// Progress for the exercise whose name normalises to the same key as
  /// [name]. Finished workouts only. Never null: an unknown exercise yields an
  /// empty progress whose displayName is the trimmed input.
  Future<ExerciseProgress> getExerciseProgress(String name);
}
