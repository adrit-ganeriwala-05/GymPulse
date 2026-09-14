import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:gympulse/domain/entities/exercise.dart';
import 'package:gympulse/domain/entities/workout.dart';
import 'package:gympulse/domain/entities/workout_draft.dart';
import 'package:gympulse/domain/repositories/settings_repository.dart';
import 'package:gympulse/domain/repositories/streak_repository.dart';
import 'package:gympulse/domain/repositories/workout_repository.dart';
import 'package:gympulse/domain/usecases/delete_workout.dart';
import 'package:gympulse/domain/usecases/discard_draft.dart';
import 'package:gympulse/domain/usecases/get_draft.dart';
import 'package:gympulse/domain/usecases/get_streak.dart';
import 'package:gympulse/domain/usecases/get_weight_unit.dart';
import 'package:gympulse/domain/usecases/get_workouts.dart';
import 'package:gympulse/domain/usecases/record_draft_elapsed.dart';
import 'package:gympulse/domain/usecases/save_draft.dart';
import 'package:gympulse/domain/usecases/save_weight_unit.dart';
import 'package:gympulse/domain/usecases/save_workout.dart';
import 'package:gympulse/domain/usecases/update_streak.dart';
import 'package:gympulse/domain/usecases/update_workout.dart';
import 'package:gympulse/injection_container.dart';
import 'package:gympulse/presentation/blocs/rest_timer/rest_timer_bloc.dart';
import 'package:gympulse/presentation/blocs/settings/settings_bloc.dart';
import 'package:gympulse/presentation/blocs/settings/settings_event.dart';
import 'package:gympulse/presentation/blocs/streak/streak_bloc.dart';
import 'package:gympulse/presentation/blocs/streak/streak_event.dart';
import 'package:gympulse/presentation/blocs/workout/workout_bloc.dart';
import 'package:gympulse/presentation/blocs/workout/workout_event.dart';
import 'package:gympulse/presentation/blocs/workout_timer/workout_timer_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeWorkoutRepo implements WorkoutRepository {
  final done = <String, Workout>{};
  Workout? draft;
  bool draftPaused = false;
  bool failReads = false;
  bool failWrites = false;
  final deleted = <String>[];

  /// When set, reads block until completed — lets tests observe loading UI.
  Completer<void>? readGate;

  @override
  Future<List<Workout>> getWorkouts() async {
    if (readGate != null) await readGate!.future;
    if (failReads) throw StateError('db unavailable');
    final l = done.values.toList()..sort((a, b) => b.date.compareTo(a.date));
    return l;
  }
  @override
  Future<void> saveWorkout(Workout w) async {
    if (failWrites) throw StateError('disk full');
    draft = null; done[w.id] = w;
  }
  @override
  Future<void> updateWorkout(Workout w) async {
    if (failWrites) throw StateError('disk full');
    done[w.id] = w;
  }
  @override
  Future<void> saveDraft(WorkoutDraft d) async { draft = d.workout; draftPaused = d.timerPaused; }
  @override
  Future<WorkoutDraft?> getDraft() async {
    if (readGate != null) await readGate!.future;
    return draft == null ? null : WorkoutDraft(workout: draft!, timerPaused: draftPaused);
  }
  @override
  Future<void> deleteWorkout(String id) async { deleted.add(id); done.remove(id); if (draft?.id == id) draft = null; }
  @override
  Future<void> recordDraftElapsed(String draftId, int elapsedSeconds, {required bool paused}) async {
    draftPaused = paused;
  }
}

class FakeStreakRepo implements StreakRepository {
  int streak = 0, rest = 2, updates = 0;
  @override
  Future<int> getStreak() async => streak;
  @override
  Future<int> getRestDaysRemaining() async => rest;
  @override
  Future<void> updateStreak() async => updates++;
  @override
  Future<void> markRestDay() async => rest--;
}

class FakeSettingsRepo implements SettingsRepository {
  String unit = 'kg';
  @override
  Future<String> getWeightUnit() async => unit;
  @override
  Future<void> saveWeightUnit(String u) async => unit = u;
}

Workout sampleWorkout({String id = 'w1', DateTime? date, int duration = 1500}) => Workout(
      id: id,
      date: date ?? DateTime.now(),
      durationSeconds: duration,
      exercises: const [Exercise(name: 'Bench', sets: [ExerciseSet(reps: 10, weight: 60)])],
    );

/// Registers fakes in get_it for screens that read via `sl<...>()`.
Future<void> registerFakes(FakeWorkoutRepo repo, {Map<String, Object> prefs = const {}}) async {
  final sl = GetIt.instance;
  await sl.reset();
  SharedPreferences.setMockInitialValues(prefs);
  sl.registerSingleton<SharedPreferences>(await SharedPreferences.getInstance());
  sl.registerSingleton(GetWorkouts(repo));
  sl.registerSingleton(GetDraft(repo));
  sl.registerSingleton(DiscardDraft(repo));
  sl.registerSingleton(DeleteWorkout(repo));
}

/// Bloc factories mirroring injection_container.dart, so `createRouter` can
/// build real routes on top of the fakes.
void registerBlocFactories(FakeWorkoutRepo repo, FakeStreakRepo streak) {
  final settings = FakeSettingsRepo();
  sl.registerFactory<WorkoutTimerBloc>(() => WorkoutTimerBloc());
  sl.registerFactory<RestTimerBloc>(() => RestTimerBloc());
  sl.registerFactory<StreakBloc>(() => StreakBloc(
        getStreak: GetStreak(streak),
        updateStreak: UpdateStreak(streak),
      ));
  sl.registerFactory<WorkoutBloc>(() => makeWorkoutBloc(repo, streak));
  sl.registerFactory<SettingsBloc>(() => SettingsBloc(
        getWeightUnit: GetWeightUnit(settings),
        saveWeightUnit: SaveWeightUnit(settings),
      ));
}

WorkoutBloc makeWorkoutBloc(FakeWorkoutRepo repo, FakeStreakRepo streak) => WorkoutBloc(
      saveWorkout: SaveWorkout(repo),
      updateWorkout: UpdateWorkout(repo),
      saveDraft: SaveDraft(repo),
      getDraft: GetDraft(repo),
      discardDraft: DiscardDraft(repo),
      recordDraftElapsed: RecordDraftElapsed(repo),
      updateStreak: UpdateStreak(streak),
    );

/// ActiveScreen's route-level providers, mirroring router.dart.
Widget activeScreenHarness(Widget child, FakeWorkoutRepo repo, FakeStreakRepo streak,
    {WorkoutEvent start = const WorkoutStarted()}) {
  final settings = FakeSettingsRepo();
  // A one-route GoRouter so the screen's `context.go('/')` on a successful
  // save resolves (to the same route) instead of asserting.
  return MaterialApp.router(
    routerConfig: GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => makeWorkoutBloc(repo, streak)..add(start)),
            BlocProvider(create: (_) => WorkoutTimerBloc()),
            BlocProvider(create: (_) => RestTimerBloc()),
            BlocProvider(
              create: (_) => SettingsBloc(
                getWeightUnit: GetWeightUnit(settings),
                saveWeightUnit: SaveWeightUnit(settings),
              )..add(const SettingsLoaded()),
            ),
          ],
          child: child,
        ),
      ),
    ]),
  );
}

Widget homeHarness(Widget child, FakeStreakRepo streak) => MaterialApp(
      home: BlocProvider(
        create: (_) => StreakBloc(
          getStreak: GetStreak(streak),
          updateStreak: UpdateStreak(streak),
        )..add(const StreakLoaded()),
        child: child,
      ),
    );

// Re-export so tests can reference the locator symbol.
GetIt get locator => sl;
