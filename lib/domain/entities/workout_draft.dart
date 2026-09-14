import 'workout.dart';

/// Snapshot of an in-progress session. [workout.durationSeconds] carries the
/// stopwatch's accumulated *active* seconds; [timerPaused] whether it was
/// paused (or stopped) at the last checkpoint, so a resume does not silently
/// restart counting time the user did not train.
class WorkoutDraft {
  final Workout workout;
  final bool timerPaused;

  const WorkoutDraft({required this.workout, this.timerPaused = false});
}
