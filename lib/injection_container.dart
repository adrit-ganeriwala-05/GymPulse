import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/datasources/streak_local_datasource.dart';
import 'data/datasources/workout_local_datasource.dart';
import 'data/repositories/settings_repository_impl.dart';
import 'data/repositories/streak_repository_impl.dart';
import 'data/repositories/workout_repository_impl.dart';
import 'domain/repositories/settings_repository.dart';
import 'domain/repositories/streak_repository.dart';
import 'domain/repositories/workout_repository.dart';
import 'domain/usecases/delete_workout.dart';
import 'domain/usecases/discard_draft.dart';
import 'domain/usecases/get_draft.dart';
import 'domain/usecases/get_streak.dart';
import 'domain/usecases/get_weight_unit.dart';
import 'domain/usecases/get_workouts.dart';
import 'domain/usecases/save_weight_unit.dart';
import 'domain/usecases/record_draft_elapsed.dart';
import 'domain/usecases/save_draft.dart';
import 'domain/usecases/save_workout.dart';
import 'domain/usecases/update_workout.dart';
import 'domain/usecases/update_streak.dart';
import 'presentation/blocs/rest_timer/rest_timer_bloc.dart';
import 'presentation/blocs/settings/settings_bloc.dart';
import 'presentation/blocs/streak/streak_bloc.dart';
import 'presentation/blocs/workout/workout_bloc.dart';
import 'presentation/blocs/workout_timer/workout_timer_bloc.dart';

final sl = GetIt.instance;

Future<void> init() async {
  final prefs = await SharedPreferences.getInstance();
  sl.registerSingleton<SharedPreferences>(prefs);

  sl.registerLazySingleton<WorkoutLocalDatasource>(
    () => WorkoutLocalDatasourceImpl(),
  );

  sl.registerSingleton<StreakLocalDatasource>(
    StreakLocalDatasourceImpl(sl<SharedPreferences>()),
  );

  sl.registerSingleton<WorkoutRepository>(
    WorkoutRepositoryImpl(sl<WorkoutLocalDatasource>()),
  );
  sl.registerSingleton<StreakRepository>(
    StreakRepositoryImpl(sl<StreakLocalDatasource>()),
  );
  sl.registerSingleton<SettingsRepository>(
    SettingsRepositoryImpl(sl<SharedPreferences>()),
  );

  sl.registerSingleton(GetWorkouts(sl<WorkoutRepository>()));
  sl.registerSingleton(SaveWorkout(sl<WorkoutRepository>()));
  // Stateless use cases: one instance is correct, so singletons not factories.
  sl.registerSingleton(UpdateWorkout(sl<WorkoutRepository>()));
  sl.registerSingleton(SaveDraft(sl<WorkoutRepository>()));
  sl.registerSingleton(GetDraft(sl<WorkoutRepository>()));
  sl.registerSingleton(DiscardDraft(sl<WorkoutRepository>()));
  sl.registerSingleton(RecordDraftElapsed(sl<WorkoutRepository>()));
  sl.registerSingleton(DeleteWorkout(sl<WorkoutRepository>()));
  sl.registerSingleton(GetStreak(sl<StreakRepository>()));
  sl.registerSingleton(UpdateStreak(sl<StreakRepository>()));
  sl.registerSingleton(GetWeightUnit(sl<SettingsRepository>()));
  sl.registerSingleton(SaveWeightUnit(sl<SettingsRepository>()));

  sl.registerFactory<WorkoutTimerBloc>(() => WorkoutTimerBloc());
  sl.registerFactory<RestTimerBloc>(() => RestTimerBloc());
  sl.registerFactory<StreakBloc>(
    () => StreakBloc(
      getStreak: sl<GetStreak>(),
      updateStreak: sl<UpdateStreak>(),
    ),
  );
  sl.registerFactory<WorkoutBloc>(
    () => WorkoutBloc(
      saveWorkout: sl<SaveWorkout>(),
      updateWorkout: sl<UpdateWorkout>(),
      saveDraft: sl<SaveDraft>(),
      getDraft: sl<GetDraft>(),
      discardDraft: sl<DiscardDraft>(),
      recordDraftElapsed: sl<RecordDraftElapsed>(),
      updateStreak: sl<UpdateStreak>(),
    ),
  );
  sl.registerFactory<SettingsBloc>(
    () => SettingsBloc(
      getWeightUnit: sl<GetWeightUnit>(),
      saveWeightUnit: sl<SaveWeightUnit>(),
    ),
  );
}
