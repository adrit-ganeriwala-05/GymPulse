import 'package:equatable/equatable.dart';

abstract class RestTimerEvent extends Equatable {
  const RestTimerEvent();

  @override
  List<Object?> get props => [];
}

class RestTimerStarted extends RestTimerEvent {
  final int duration;

  // When resuming a paused timer we restart the periodic stream from the
  // remaining seconds, but the progress ring's denominator must stay the
  // original total. If null, [duration] is used as the total (fresh start).
  final int? totalDuration;

  const RestTimerStarted(this.duration, {this.totalDuration});

  @override
  List<Object?> get props => [duration, totalDuration];
}

class RestTimerTicked extends RestTimerEvent {
  final int remaining;

  const RestTimerTicked(this.remaining);

  @override
  List<Object?> get props => [remaining];
}

class RestTimerPaused extends RestTimerEvent {
  const RestTimerPaused();
}

class RestTimerResumed extends RestTimerEvent {
  const RestTimerResumed();
}

class RestTimerReset extends RestTimerEvent {
  const RestTimerReset();
}
