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
    if (event.paused) {
      emit(WorkoutTimerPausedState(event.from));
      return;
    }
    emit(WorkoutTimerRunningState(event.from));
    _subscription = Stream.periodic(
      const Duration(seconds: 1),
      (i) => event.from + i + 1,
    ).listen((seconds) => add(WorkoutTimerTicked(seconds)));
  }

  void _onTicked(
    WorkoutTimerTicked event,
    Emitter<WorkoutTimerState> emit,
  ) {
    emit(WorkoutTimerRunningState(event.seconds));
  }

  /// The clock's current reading whether it is running or paused. Reading
  /// only from the running state zeroed a paused clock on Stop/Pause, which
  /// the save-retry path, edit mode and the draft checkpoint all rely on.
  int get _seconds => switch (state) {
        WorkoutTimerRunningState s => s.seconds,
        WorkoutTimerPausedState s => s.seconds,
        WorkoutTimerStoppedState s => s.seconds,
        _ => 0,
      };

  void _onStopped(
    WorkoutTimerStopped event,
    Emitter<WorkoutTimerState> emit,
  ) {
    _subscription?.cancel();
    emit(WorkoutTimerStoppedState(_seconds));
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
    // Only a running clock can be paused; a second Pause (double tap before
    // the button swaps to Resume) must not reset the reading.
    if (state is! WorkoutTimerRunningState) return;
    _subscription?.cancel();
    emit(WorkoutTimerPausedState(_seconds));
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
