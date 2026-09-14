import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/domain/entities/exercise.dart';
import 'package:gympulse/domain/entities/workout.dart';
import 'package:gympulse/domain/repositories/streak_repository.dart';
import 'package:gympulse/domain/repositories/workout_repository.dart';
import 'package:gympulse/domain/usecases/discard_draft.dart';
import 'package:gympulse/domain/usecases/get_draft.dart';
import 'package:gympulse/domain/usecases/save_draft.dart';
import 'package:gympulse/domain/usecases/save_workout.dart';
import 'package:gympulse/domain/usecases/update_streak.dart';
import 'package:gympulse/domain/usecases/update_workout.dart';
import 'package:gympulse/presentation/blocs/workout/workout_bloc.dart';
import 'package:gympulse/presentation/blocs/workout/workout_event.dart';
import 'package:gympulse/presentation/blocs/workout/workout_state.dart';

/// In-memory repository: records exactly what the bloc asked it to do.
class FakeWorkoutRepo implements WorkoutRepository {
  final done = <String, Workout>{};
  Workout? draft;
  int saveCalls = 0, updateCalls = 0, draftWrites = 0;
  bool failSave = false;

  @override
  Future<List<Workout>> getWorkouts() async => done.values.toList();
  @override
  Future<void> saveWorkout(Workout w) async {
    if (failSave) throw StateError('disk full');
    saveCalls++;
    if (draft?.id == w.id) draft = null;
    done[w.id] = w;
  }
  @override
  Future<void> updateWorkout(Workout w) async {
    updateCalls++;
    done[w.id] = w;
  }
  @override
  Future<void> saveDraft(Workout w) async {
    draftWrites++;
    draft = w;
  }
  @override
  Future<Workout?> getDraft() async => draft;
  @override
  Future<void> deleteWorkout(String id) async {
    if (draft?.id == id) draft = null;
    done.remove(id);
  }
}

class FakeStreakRepo implements StreakRepository {
  int updates = 0;
  @override
  Future<int> getStreak() async => 0;
  @override
  Future<int> getRestDaysRemaining() async => 2;
  @override
  Future<void> updateStreak() async => updates++;
  @override
  Future<void> markRestDay() async {}
}

void main() {
  late FakeWorkoutRepo repo;
  late FakeStreakRepo streak;
  late WorkoutBloc bloc;
  final t0 = DateTime(2025, 6, 2, 18);

  WorkoutBloc make() => WorkoutBloc(
        saveWorkout: SaveWorkout(repo),
        updateWorkout: UpdateWorkout(repo),
        saveDraft: SaveDraft(repo),
        getDraft: GetDraft(repo),
        discardDraft: DiscardDraft(repo),
        updateStreak: UpdateStreak(streak),
        clock: () => t0,
      );

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  setUp(() {
    repo = FakeWorkoutRepo();
    streak = FakeStreakRepo();
    bloc = make();
  });
  tearDown(() => bloc.close());

  WorkoutInProgressState inProgress() => bloc.state as WorkoutInProgressState;

  test('start with no draft → fresh session dated now', () async {
    bloc.add(const WorkoutStarted());
    await settle();
    expect(bloc.state, isA<WorkoutInProgressState>());
    expect(inProgress().startedAt, t0);
    expect(inProgress().exercises, isEmpty);
    expect(inProgress().isEditing, isFalse);
  });

  test('every mutation writes through to the draft', () async {
    bloc.add(const WorkoutStarted());
    await settle();
    bloc.add(const ExerciseAdded('Bench'));
    bloc.add(const SetLogged(exerciseName: 'Bench', reps: 5, weight: 100));
    bloc.add(const SetRemoved(exerciseName: 'Bench', setIndex: 0));
    bloc.add(const ExerciseRemoved('Bench'));
    await settle();
    expect(repo.draftWrites, 4);
    expect(repo.draft!.id, inProgress().id);
    expect(repo.draft!.exercises, isEmpty);
  });

  test('start with a draft → resumes it with the same id and start time', () async {
    repo.draft = Workout(
      id: 'draft-1',
      date: DateTime(2025, 6, 2, 17),
      durationSeconds: 0,
      exercises: const [Exercise(name: 'Squat', sets: [ExerciseSet(reps: 5, weight: 80)])],
    );
    bloc.add(const WorkoutStarted());
    await settle();
    expect(inProgress().id, 'draft-1');
    expect(inProgress().startedAt, DateTime(2025, 6, 2, 17));
    expect(inProgress().exercises.single.name, 'Squat');
  });

  test('finish saves under the draft id, clears the draft, bumps the streak', () async {
    bloc.add(const WorkoutStarted());
    await settle();
    bloc.add(const ExerciseAdded('Bench'));
    await settle();
    final id = inProgress().id;
    bloc.add(const WorkoutFinished(durationSeconds: 900));
    await settle();
    expect(bloc.state, isA<WorkoutCompleteState>());
    expect(repo.done[id]!.date, t0);
    expect(repo.done[id]!.durationSeconds, 900);
    expect(repo.draft, isNull);
    expect(streak.updates, 1);
  });

  test('save failure returns to an editable state (BUG-26)', () async {
    bloc.add(const WorkoutStarted());
    await settle();
    bloc.add(const ExerciseAdded('Bench'));
    await settle();
    repo.failSave = true;
    final seen = <WorkoutState>[];
    final sub = bloc.stream.listen(seen.add);
    bloc.add(const WorkoutFinished(durationSeconds: 1));
    await settle();
    await sub.cancel();
    expect(seen.map((s) => s.runtimeType),
        [WorkoutErrorState, WorkoutInProgressState]);
    // The user can now remove the exercise and retry.
    bloc.add(const ExerciseRemoved('Bench'));
    await settle();
    expect(inProgress().exercises, isEmpty);
    expect(streak.updates, 0);
  });

  test('discard deletes the draft and returns to initial', () async {
    bloc.add(const WorkoutStarted());
    await settle();
    bloc.add(const ExerciseAdded('Bench'));
    await settle();
    bloc.add(const WorkoutDiscarded());
    await settle();
    expect(repo.draft, isNull);
    expect(bloc.state, isA<WorkoutInitialState>());
  });

  group('edit mode', () {
    final saved = Workout(
      id: 'w-9',
      date: DateTime(2025, 5, 1, 9),
      durationSeconds: 1800,
      exercises: const [Exercise(name: 'Row', sets: [ExerciseSet(reps: 10, weight: 40)])],
    );

    test('edit start seeds state and never writes a draft', () async {
      bloc.add(WorkoutEditStarted(saved));
      await settle();
      expect(inProgress().isEditing, isTrue);
      expect(inProgress().id, 'w-9');
      bloc.add(const SetLogged(exerciseName: 'Row', reps: 8, weight: 45));
      await settle();
      expect(repo.draftWrites, 0);
      expect(repo.draft, isNull);
    });

    test('finish in edit mode updates in place, keeps date, skips streak', () async {
      bloc.add(WorkoutEditStarted(saved));
      await settle();
      bloc.add(const WorkoutFinished(durationSeconds: 2000));
      await settle();
      expect(repo.updateCalls, 1);
      expect(repo.saveCalls, 0);
      expect(repo.done['w-9']!.date, saved.date);
      expect(repo.done['w-9']!.durationSeconds, 2000);
      expect(streak.updates, 0);
    });
  });
}
