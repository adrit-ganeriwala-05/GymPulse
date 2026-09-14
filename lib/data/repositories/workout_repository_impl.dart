import '../../domain/entities/workout.dart';
import '../../domain/entities/workout_draft.dart';
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
  Future<void> saveDraft(WorkoutDraft draft) => datasource.upsertWorkout(
        WorkoutModel.fromEntity(draft.workout),
        status: WorkoutLocalDatasourceImpl.statusDraft,
        timerPaused: draft.timerPaused,
      );

  @override
  Future<WorkoutDraft?> getDraft() async {
    final row = await datasource.getDraft();
    if (row == null) return null;
    return WorkoutDraft(workout: row.workout, timerPaused: row.timerPaused);
  }

  @override
  Future<void> deleteWorkout(String id) => datasource.deleteWorkout(id);

  @override
  Future<void> discardAllDrafts() => datasource.deleteDrafts();

  @override
  Future<void> recordDraftElapsed(
    String draftId,
    int elapsedSeconds, {
    required bool paused,
  }) =>
      datasource.updateDraftElapsed(draftId, elapsedSeconds, paused: paused);
}
