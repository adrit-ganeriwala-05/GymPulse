import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'rest_timer_event.dart';
import 'rest_timer_state.dart';

const _defaultDuration = 60;

class RestTimerBloc extends Bloc<RestTimerEvent, RestTimerState> {
  StreamSubscription<int>? _subscription;

  RestTimerBloc() : super(const RestTimerInitialState(_defaultDuration)) {
    on<RestTimerStarted>(_onStarted);
    on<RestTimerTicked>(_onTicked);
    on<RestTimerPaused>(_onPaused);
    on<RestTimerResumed>(_onResumed);
    on<RestTimerReset>(_onReset);
  }

  void _onStarted(RestTimerStarted event, Emitter<RestTimerState> emit) {
    _subscription?.cancel();
    final duration = event.duration;
    final total = event.totalDuration ?? duration;
    emit(RestTimerRunningState(duration, totalDuration: total));
    _subscription = Stream.periodic(
      const Duration(seconds: 1),
      (i) => i + 1,
    ).take(duration).listen((tick) {
      add(RestTimerTicked(duration - tick));
    });
  }

  void _onTicked(RestTimerTicked event, Emitter<RestTimerState> emit) {
    if (event.remaining <= 0) {
      _subscription?.cancel();
      emit(const RestTimerFinishedState());
    } else {
      final total = state is RestTimerRunningState
          ? (state as RestTimerRunningState).totalDuration
          : _defaultDuration;
      emit(RestTimerRunningState(event.remaining, totalDuration: total));
    }
  }

  void _onPaused(RestTimerPaused event, Emitter<RestTimerState> emit) {
    _subscription?.cancel();
    if (state is RestTimerRunningState) {
      final running = state as RestTimerRunningState;
      emit(RestTimerPausedState(
        running.seconds,
        totalDuration: running.totalDuration,
      ));
    }
  }

  void _onResumed(RestTimerResumed event, Emitter<RestTimerState> emit) {
    if (state is RestTimerPausedState) {
      final paused = state as RestTimerPausedState;
      add(RestTimerStarted(
        paused.seconds,
        totalDuration: paused.totalDuration,
      ));
    }
  }

  void _onReset(RestTimerReset event, Emitter<RestTimerState> emit) {
    _subscription?.cancel();
    emit(const RestTimerInitialState(_defaultDuration));
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
