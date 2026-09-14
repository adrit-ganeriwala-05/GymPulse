import '../../domain/entities/workout.dart';
import '../../domain/repositories/workout_repository.dart';
import '../datasources/workout_local_datasource.dart';
import '../models/workout_model.dart';

class WorkoutRepositoryImpl implements WorkoutRepository {
  final WorkoutLocalDatasource datasource;

  const WorkoutRepositoryImpl(this.datasource);

  @override
  Future<List<Workout>> getWorkouts() => datasource.getWorkouts();

  @override
  Future<void> saveWorkout(Workout workout) => datasource.upsertWorkout(
        WorkoutModel.fromEntity(workout),
        status: WorkoutLocalDatasourceImpl.statusDone,
      );

  @override
  Future<void> updateWorkout(Workout workout) => saveWorkout(workout);

  @override
  Future<void> saveDraft(Workout workout) => datasource.upsertWorkout(
        WorkoutModel.fromEntity(workout),
        status: WorkoutLocalDatasourceImpl.statusDraft,
      );

  @override
  Future<Workout?> getDraft() => datasource.getDraft();

  @override
  Future<void> deleteWorkout(String id) => datasource.deleteWorkout(id);
}
