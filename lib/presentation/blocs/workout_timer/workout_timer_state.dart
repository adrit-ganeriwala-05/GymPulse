import 'package:equatable/equatable.dart';

abstract class WorkoutTimerState extends Equatable {
  const WorkoutTimerState();

  @override
  List<Object?> get props => [];
}

class WorkoutTimerInitialState extends WorkoutTimerState {
  const WorkoutTimerInitialState();
}

class WorkoutTimerRunningState extends WorkoutTimerState {
  final int seconds;

  const WorkoutTimerRunningState(this.seconds);

  @override
  List<Object?> get props => [seconds];
}

class WorkoutTimerStoppedState extends WorkoutTimerState {
  final int seconds;

  const WorkoutTimerStoppedState(this.seconds);

  @override
  List<Object?> get props => [seconds];
}

class WorkoutTimerPausedState extends WorkoutTimerState {
  final int seconds;

  const WorkoutTimerPausedState(this.seconds);

  @override
  List<Object?> get props => [seconds];
}
