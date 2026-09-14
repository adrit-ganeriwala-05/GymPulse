import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/presentation/blocs/workout_timer/workout_timer_bloc.dart';
import 'package:gympulse/presentation/blocs/workout_timer/workout_timer_event.dart';
import 'package:gympulse/presentation/blocs/workout_timer/workout_timer_state.dart';

/// Stream.periodic under fakeAsync: `elapse` fires the ticks and flushes the
/// bloc's event microtasks, so timing is exact and the suite runs in ms.
void main() {
  int secs(WorkoutTimerBloc b) => switch (b.state) {
        WorkoutTimerRunningState s => s.seconds,
        WorkoutTimerPausedState s => s.seconds,
        WorkoutTimerStoppedState s => s.seconds,
        _ => -1,
      };

  test('start ticks once per second from zero', () {
    fakeAsync((async) {
      final b = WorkoutTimerBloc()..add(const WorkoutTimerStarted());
      async.elapse(const Duration(seconds: 3));
      expect(b.state, const WorkoutTimerRunningState(3));
      b.close();
    });
  });

  test('start seeds from `from` (resumed draft / edit)', () {
    fakeAsync((async) {
      final b = WorkoutTimerBloc()..add(const WorkoutTimerStarted(from: 130));
      async.flushMicrotasks();
      expect(b.state, const WorkoutTimerRunningState(130));
      async.elapse(const Duration(seconds: 2));
      expect(b.state, const WorkoutTimerRunningState(132));
      b.close();
    });
  });

  test('start paused: no ticks accrue (draft paused at death)', () {
    fakeAsync((async) {
      final b = WorkoutTimerBloc()
        ..add(const WorkoutTimerStarted(from: 300, paused: true));
      async.elapse(const Duration(seconds: 10));
      expect(b.state, const WorkoutTimerPausedState(300));
      expect(async.periodicTimerCount, 0, reason: 'no subscription created');
      b.close();
    });
  });

  test('double start does not double the tick rate', () {
    fakeAsync((async) {
      final b = WorkoutTimerBloc()
        ..add(const WorkoutTimerStarted())
        ..add(const WorkoutTimerStarted());
      async.elapse(const Duration(seconds: 4));
      expect(secs(b), 4);
      expect(async.periodicTimerCount, 1, reason: 'old subscription cancelled');
      b.close();
    });
  });

  test('pause freezes, resume continues, double resume is a no-op', () {
    fakeAsync((async) {
      final b = WorkoutTimerBloc()..add(const WorkoutTimerStarted());
      async.elapse(const Duration(seconds: 5));
      b.add(const WorkoutTimerPaused());
      async.elapse(const Duration(seconds: 10));
      expect(b.state, const WorkoutTimerPausedState(5));
      b
        ..add(const WorkoutTimerResumed())
        ..add(const WorkoutTimerResumed());
      async.elapse(const Duration(seconds: 3));
      expect(b.state, const WorkoutTimerRunningState(8));
      expect(async.periodicTimerCount, 1);
      b.close();
    });
  });

  test('stop keeps the reading; reset returns to initial and cancels', () {
    fakeAsync((async) {
      final b = WorkoutTimerBloc()..add(const WorkoutTimerStarted());
      async.elapse(const Duration(seconds: 7));
      b.add(const WorkoutTimerStopped());
      async.elapse(const Duration(seconds: 5));
      expect(b.state, const WorkoutTimerStoppedState(7));
      b.add(const WorkoutTimerReset());
      async.flushMicrotasks();
      expect(b.state, const WorkoutTimerInitialState());
      expect(async.periodicTimerCount, 0);
      b.close();
    });
  });

  test('close() cancels the subscription; no ticks after close', () {
    fakeAsync((async) {
      final b = WorkoutTimerBloc()..add(const WorkoutTimerStarted());
      async.elapse(const Duration(seconds: 2));
      b.close();
      async.flushMicrotasks();
      expect(async.periodicTimerCount, 0);
      async.elapse(const Duration(seconds: 5)); // would throw if a tick added
      expect(async.periodicTimerCount, 0);
    });
  });
}
