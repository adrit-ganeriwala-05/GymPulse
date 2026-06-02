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

class WorkoutInProgressState extends WorkoutState {
  final List<Exercise> exercises;

  const WorkoutInProgressState({required this.exercises});

  @override
  List<Object?> get props => [exercises];
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

class WorkoutHistoryState extends WorkoutState {
  final List<Workout> workouts;

  const WorkoutHistoryState({required this.workouts});

  @override
  List<Object?> get props => [workouts];
}
