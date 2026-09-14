import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/data/datasources/workout_local_datasource.dart';
import 'package:gympulse/data/models/workout_model.dart';
import 'package:gympulse/data/repositories/workout_repository_impl.dart';
import 'package:gympulse/domain/entities/exercise.dart';
import 'package:gympulse/domain/entities/workout.dart';
import 'package:gympulse/domain/entities/workout_draft.dart';

/// Records every call so the status/paused policy the repository encodes is
/// asserted, not assumed.
class RecordingDatasource implements WorkoutLocalDatasource {
  final calls = <String>[];
  WorkoutModel? last;
  ({WorkoutModel workout, bool timerPaused})? draft;

  @override
  Future<void> upsertWorkout(WorkoutModel workout, {required String status, bool timerPaused = false}) async {
    calls.add('upsert:$status:$timerPaused');
    last = workout;
  }
  @override
  Future<List<WorkoutModel>> getWorkouts() async => [];
  @override
  Future<({WorkoutModel workout, bool timerPaused})?> getDraft() async => draft;
  @override
  Future<void> deleteWorkout(String id) async => calls.add('delete:$id');
  @override
  Future<void> updateDraftElapsed(String id, int elapsedSeconds, {required bool paused}) async =>
      calls.add('elapsed:$id:$elapsedSeconds:$paused');
}

void main() {
  final entity = Workout(
    id: 'w', date: DateTime(2025, 6, 2), durationSeconds: 10,
    exercises: const [
      Exercise(name: 'A', sets: [ExerciseSet(reps: 5, weight: 61.2349), ExerciseSet(reps: 3, weight: 70)]),
      Exercise(name: 'B', sets: []),
    ],
  );

  test('save → done, update → done, draft → draft (+paused), delete, elapsed', () async {
    final ds = RecordingDatasource();
    final repo = WorkoutRepositoryImpl(ds);
    await repo.saveWorkout(entity);
    await repo.updateWorkout(entity);
    await repo.saveDraft(WorkoutDraft(workout: entity, timerPaused: true));
    await repo.deleteWorkout('w');
    await repo.recordDraftElapsed('w', 42, paused: false);
    expect(ds.calls, [
      'upsert:done:false', 'upsert:done:false', 'upsert:draft:true', 'delete:w', 'elapsed:w:42:false',
    ]);
  });

  test('entity → model mapping preserves order, sets and exact weights', () async {
    final ds = RecordingDatasource();
    await WorkoutRepositoryImpl(ds).saveWorkout(entity);
    final m = ds.last!;
    expect(m.id, 'w');
    expect(m.exerciseModels.map((e) => e.name), ['A', 'B']);
    expect(m.exerciseModels.first.modelSets.map((s) => s.weight), [61.2349, 70]);
    expect(m.exerciseModels.first.modelSets.map((s) => s.reps), [5, 3]);
    expect(m.exercises, same(m.exerciseModels), reason: 'entity view is the same list');
  });

  test('getDraft maps the record into a WorkoutDraft', () async {
    final ds = RecordingDatasource()
      ..draft = (workout: WorkoutModel.fromEntity(entity), timerPaused: true);
    final d = await WorkoutRepositoryImpl(ds).getDraft();
    expect(d!.workout.id, 'w');
    expect(d.timerPaused, isTrue);
    ds.draft = null;
    expect(await WorkoutRepositoryImpl(ds).getDraft(), isNull);
  });
}
