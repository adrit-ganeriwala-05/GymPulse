import 'package:equatable/equatable.dart';

import '../../../domain/entities/exercise.dart';
import '../../../domain/entities/workout.dart';

abstract class WorkoutState extends Equatable {
  const WorkoutState();

  @override
  List<Object?> get props => [];
}

class WorkoutInitialState extends WorkoutState {
  const WorkoutInitialState();
}

/// Draft lookup in flight. A real state so the Active screen never renders
/// an empty session before it knows whether one is being resumed.
class WorkoutLoadingState extends WorkoutState {
  const WorkoutLoadingState();
}

class WorkoutInProgressState extends WorkoutState {
  /// Stable for the whole session; the draft row and the finished row share it.
  final String id;

  /// Captured when the session begins. The saved workout is dated from this,
  /// not from the finish tap, so a session crossing midnight files under the
  /// day it started (BUG-06).
  final DateTime startedAt;

  final List<Exercise> exercises;

  /// Accumulated stopwatch seconds, persisted with the draft. Derived from
  /// the timer, never from wall-clock age, so a draft resumed days later does
  /// not read as a 72-hour workout.
  final int elapsedSeconds;

  /// Non-null when editing an already-finished workout: mutations skip draft
  /// persistence and Finish updates in place without touching the streak.
  final Workout? editing;

  const WorkoutInProgressState({
    required this.id,
    required this.startedAt,
    required this.exercises,
    this.elapsedSeconds = 0,
    this.editing,
  });

  bool get isEditing => editing != null;

  WorkoutInProgressState copyWith({
    List<Exercise>? exercises,
    int? elapsedSeconds,
  }) =>
      WorkoutInProgressState(
        id: id,
        startedAt: startedAt,
        exercises: exercises ?? this.exercises,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        editing: editing,
      );

  @override
  List<Object?> get props => [id, startedAt, exercises, elapsedSeconds, editing];
}

class WorkoutCompleteState extends WorkoutState {
  final Workout workout;

  const WorkoutCompleteState({required this.workout});

  @override
  List<Object?> get props => [workout];
}

// FIX: error state so save failures surface instead of silently dropping
class WorkoutErrorState extends WorkoutState {
  final String message;
  final List<Exercise> exercises;

  const WorkoutErrorState({
    required this.message,
    required this.exercises,
  });

  @override
  List<Object?> get props => [message, exercises];
}
