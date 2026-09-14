import 'package:equatable/equatable.dart';

abstract class WorkoutTimerEvent extends Equatable {
  const WorkoutTimerEvent();

  @override
  List<Object?> get props => [];
}

class WorkoutTimerStarted extends WorkoutTimerEvent {
  /// Seconds already elapsed — non-zero when resuming a draft or editing.
  final int from;

  const WorkoutTimerStarted({this.from = 0});

  @override
  List<Object?> get props => [from];
}

class WorkoutTimerTicked extends WorkoutTimerEvent {
  final int seconds;

  const WorkoutTimerTicked(this.seconds);

  @override
  List<Object?> get props => [seconds];
}

class WorkoutTimerStopped extends WorkoutTimerEvent {
  const WorkoutTimerStopped();
}

class WorkoutTimerReset extends WorkoutTimerEvent {
  const WorkoutTimerReset();
}

class WorkoutTimerPaused extends WorkoutTimerEvent {
  const WorkoutTimerPaused();
}

class WorkoutTimerResumed extends WorkoutTimerEvent {
  const WorkoutTimerResumed();
}
