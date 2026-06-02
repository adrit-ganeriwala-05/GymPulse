import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'workout_timer_event.dart';
import 'workout_timer_state.dart';

class WorkoutTimerBloc extends Bloc<WorkoutTimerEvent, WorkoutTimerState> {
  StreamSubscription<int>? _subscription;

  WorkoutTimerBloc() : super(const WorkoutTimerInitialState()) {
    on<WorkoutTimerStarted>(_onStarted);
    on<WorkoutTimerTicked>(_onTicked);
    on<WorkoutTimerStopped>(_onStopped);
    on<WorkoutTimerReset>(_onReset);
    on<WorkoutTimerPaused>(_onPaused);
    on<WorkoutTimerResumed>(_onResumed);
  }

  void _onStarted(
    WorkoutTimerStarted event,
    Emitter<WorkoutTimerState> emit,
  ) {
    _subscription?.cancel();
    emit(const WorkoutTimerRunningState(0));
    _subscription = Stream.periodic(
      const Duration(seconds: 1),
      (i) => i + 1,
    ).listen((seconds) => add(WorkoutTimerTicked(seconds)));
  }

  void _onTicked(
    WorkoutTimerTicked event,
    Emitter<WorkoutTimerState> emit,
  ) {
    emit(WorkoutTimerRunningState(event.seconds));
  }

  void _onStopped(
    WorkoutTimerStopped event,
    Emitter<WorkoutTimerState> emit,
  ) {
    _subscription?.cancel();
    final seconds =
        state is WorkoutTimerRunningState
            ? (state as WorkoutTimerRunningState).seconds
            : 0;
    emit(WorkoutTimerStoppedState(seconds));
  }

  void _onReset(
    WorkoutTimerReset event,
    Emitter<WorkoutTimerState> emit,
  ) {
    _subscription?.cancel();
    emit(const WorkoutTimerInitialState());
  }

  void _onPaused(
    WorkoutTimerPaused event,
    Emitter<WorkoutTimerState> emit,
  ) {
    _subscription?.cancel();
    final seconds = state is WorkoutTimerRunningState
        ? (state as WorkoutTimerRunningState).seconds
        : 0;
    emit(WorkoutTimerPausedState(seconds));
  }

  void _onResumed(
    WorkoutTimerResumed event,
    Emitter<WorkoutTimerState> emit,
  ) {
    if (state is! WorkoutTimerPausedState) return;
    final pausedSeconds = (state as WorkoutTimerPausedState).seconds;
    emit(WorkoutTimerRunningState(pausedSeconds));
    _subscription = Stream.periodic(
      const Duration(seconds: 1),
      (i) => pausedSeconds + i + 1,
    ).listen((seconds) => add(WorkoutTimerTicked(seconds)));
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
