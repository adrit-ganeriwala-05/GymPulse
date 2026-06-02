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
  Future<void> saveWorkout(Workout workout) =>
      datasource.saveWorkout(WorkoutModel.fromEntity(workout));
}
