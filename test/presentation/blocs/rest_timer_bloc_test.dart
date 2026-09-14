import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/presentation/blocs/rest_timer/rest_timer_bloc.dart';
import 'package:gympulse/presentation/blocs/rest_timer/rest_timer_event.dart';
import 'package:gympulse/presentation/blocs/rest_timer/rest_timer_state.dart';

void main() {
  test('counts down and finishes exactly at zero', () {
    fakeAsync((async) {
      final b = RestTimerBloc()..add(const RestTimerStarted(3));
      async.flushMicrotasks();
      expect(b.state, const RestTimerRunningState(3, totalDuration: 3));
      async.elapse(const Duration(seconds: 1));
      expect(b.state, const RestTimerRunningState(2, totalDuration: 3));
      async.elapse(const Duration(seconds: 2));
      expect(b.state, const RestTimerFinishedState());
      expect(async.periodicTimerCount, 0, reason: 'take(n) + cancel');
      b.close();
    });
  });

  test('pause/resume keeps the original total for the progress ring', () {
    fakeAsync((async) {
      final b = RestTimerBloc()..add(const RestTimerStarted(60));
      async.elapse(const Duration(seconds: 10));
      b.add(const RestTimerPaused());
      async.elapse(const Duration(seconds: 30));
      expect(b.state, const RestTimerPausedState(50, totalDuration: 60));
      b.add(const RestTimerResumed());
      async.elapse(const Duration(seconds: 5));
      expect(b.state, const RestTimerRunningState(45, totalDuration: 60));
      b.close();
    });
  });

  test('restart while running cancels the first countdown', () {
    fakeAsync((async) {
      final b = RestTimerBloc()..add(const RestTimerStarted(30));
      async.elapse(const Duration(seconds: 5));
      b.add(const RestTimerStarted(90));
      async.elapse(const Duration(seconds: 5));
      expect(b.state, const RestTimerRunningState(85, totalDuration: 90));
      expect(async.periodicTimerCount, 1);
      b.close();
    });
  });

  test('reset returns to the default and cancels; close cancels', () {
    fakeAsync((async) {
      final b = RestTimerBloc()..add(const RestTimerStarted(30));
      async.elapse(const Duration(seconds: 2));
      b.add(const RestTimerReset());
      async.flushMicrotasks();
      expect(b.state, const RestTimerInitialState(60));
      expect(async.periodicTimerCount, 0);
      b.add(const RestTimerStarted(30));
      async.elapse(const Duration(seconds: 1));
      b.close();
      async.flushMicrotasks();
      expect(async.periodicTimerCount, 0);
    });
  });
}
