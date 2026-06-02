import 'package:equatable/equatable.dart';

abstract class RestTimerState extends Equatable {
  const RestTimerState();

  @override
  List<Object?> get props => [];
}

class RestTimerInitialState extends RestTimerState {
  final int seconds;

  const RestTimerInitialState(this.seconds);

  @override
  List<Object?> get props => [seconds];
}

class RestTimerRunningState extends RestTimerState {
  final int seconds;
  final int totalDuration;

  const RestTimerRunningState(this.seconds, {required this.totalDuration});

  @override
  List<Object?> get props => [seconds, totalDuration];
}

class RestTimerPausedState extends RestTimerState {
  final int seconds;
  final int totalDuration;

  const RestTimerPausedState(this.seconds, {required this.totalDuration});

  @override
  List<Object?> get props => [seconds, totalDuration];
}

class RestTimerFinishedState extends RestTimerState {
  const RestTimerFinishedState();
}
