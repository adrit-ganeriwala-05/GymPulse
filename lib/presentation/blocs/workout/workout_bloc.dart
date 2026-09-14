import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/entities/exercise.dart';
import '../../../domain/entities/workout.dart';
import '../../../domain/entities/workout_draft.dart';
import '../../../domain/usecases/discard_draft.dart';
import '../../../domain/usecases/get_draft.dart';
import '../../../domain/usecases/record_draft_elapsed.dart';
import '../../../domain/usecases/save_draft.dart';
import '../../../domain/usecases/save_workout.dart';
import '../../../domain/usecases/update_streak.dart';
import '../../../domain/usecases/update_workout.dart';
import 'workout_event.dart';
import 'workout_state.dart';

/// Active-session state machine.
///
/// Every mutation is written through to the draft row immediately, so the
/// session survives backgrounding, navigation and process death without any
/// lifecycle hook (AppLifecycleState.paused does not fire on a kill).
/// Editing an already-finished workout reuses the same states with
/// [WorkoutInProgressState.editing] set; edits never write a draft and never
/// touch the streak.
class WorkoutBloc extends Bloc<WorkoutEvent, WorkoutState> {
  final SaveWorkout saveWorkout;
  final UpdateWorkout updateWorkout;
  final SaveDraft saveDraft;
  final GetDraft getDraft;
  final DiscardDraft discardDraft;
  final RecordDraftElapsed recordDraftElapsed;
  final UpdateStreak updateStreak;

  /// Injectable clock; stamps [WorkoutInProgressState.startedAt].
  final DateTime Function() now;

  WorkoutBloc({
    required this.saveWorkout,
    required this.updateWorkout,
    required this.saveDraft,
    required this.getDraft,
    required this.discardDraft,
    required this.recordDraftElapsed,
    required this.updateStreak,
    DateTime Function()? clock,
  })  : now = clock ?? DateTime.now,
        super(const WorkoutInitialState()) {
    on<WorkoutStarted>(_onStarted);
    on<WorkoutEditStarted>(_onEditStarted);
    // Mutations are read-emit-persist; serialise them so two quick taps
    // cannot persist an older snapshot after a newer one.
    on<ExerciseAdded>(_onExerciseAdded, transformer: sequential());
    on<SetLogged>(_onSetLogged, transformer: sequential());
    on<SetRemoved>(_onSetRemoved, transformer: sequential());
    on<ExerciseRemoved>(_onExerciseRemoved, transformer: sequential());
    on<WorkoutElapsedUpdated>(_onElapsedUpdated, transformer: sequential());
    on<WorkoutDiscarded>(_onDiscarded);
    on<WorkoutFinished>(_onFinished);
  }

  Future<void> _onStarted(
    WorkoutStarted event,
    Emitter<WorkoutState> emit,
  ) async {
    emit(const WorkoutLoadingState());
    WorkoutDraft? draft;
    try {
      draft = await getDraft();
    } catch (e, s) {
      addError(e, s);
    }
    if (draft != null) {
      final w = draft.workout;
      emit(WorkoutInProgressState(
        id: w.id,
        startedAt: w.date,
        exercises: w.exercises,
        elapsedSeconds: w.durationSeconds,
        timerPaused: draft.timerPaused,
      ));
    } else {
      emit(WorkoutInProgressState(
        id: const Uuid().v4(),
        startedAt: now(),
        exercises: const [],
      ));
    }
  }

  void _onEditStarted(WorkoutEditStarted event, Emitter<WorkoutState> emit) {
    final w = event.workout;
    emit(WorkoutInProgressState(
      id: w.id,
      startedAt: w.date,
      exercises: w.exercises,
      editing: w,
    ));
  }

  Future<void> _onExerciseAdded(
    ExerciseAdded event,
    Emitter<WorkoutState> emit,
  ) async {
    if (state is! WorkoutInProgressState) return;
    final current = state as WorkoutInProgressState;
    if (current.exercises.any((e) => e.name == event.name)) return;
    final next = current.copyWith(exercises: [
      ...current.exercises,
      Exercise(name: event.name, sets: const []),
    ]);
    emit(next);
    await _persist(next);
  }

  Future<void> _onSetLogged(SetLogged event, Emitter<WorkoutState> emit) async {
    if (state is! WorkoutInProgressState) return;
    final current = state as WorkoutInProgressState;
    final exercises = List<Exercise>.from(current.exercises);
    final newSet = ExerciseSet(reps: event.reps, weight: event.weight);

    final idx = exercises.indexWhere((e) => e.name == event.exerciseName);
    if (idx == -1) {
      exercises.add(Exercise(name: event.exerciseName, sets: [newSet]));
    } else {
      final existing = exercises[idx];
      exercises[idx] = Exercise(
        name: existing.name,
        sets: [...existing.sets, newSet],
      );
    }
    final next = current.copyWith(exercises: exercises);
    emit(next);
    await _persist(next);
  }

  Future<void> _onSetRemoved(SetRemoved event, Emitter<WorkoutState> emit) async {
    if (state is! WorkoutInProgressState) return;
    final current = state as WorkoutInProgressState;
    final exercises = current.exercises.map((e) {
      if (e.name != event.exerciseName) return e;
      if (event.setIndex < 0 || event.setIndex >= e.sets.length) return e;
      final sets = List<ExerciseSet>.from(e.sets)..removeAt(event.setIndex);
      return Exercise(name: e.name, sets: sets);
    }).toList();
    final next = current.copyWith(exercises: exercises);
    emit(next);
    await _persist(next);
  }

  Future<void> _onExerciseRemoved(
    ExerciseRemoved event,
    Emitter<WorkoutState> emit,
  ) async {
    if (state is! WorkoutInProgressState) return;
    final current = state as WorkoutInProgressState;
    final next = current.copyWith(
      exercises: current.exercises.where((e) => e.name != event.name).toList(),
    );
    emit(next);
    await _persist(next);
  }

  Future<void> _onElapsedUpdated(
    WorkoutElapsedUpdated event,
    Emitter<WorkoutState> emit,
  ) async {
    if (state is! WorkoutInProgressState) return;
    final current = state as WorkoutInProgressState;
    if (current.isEditing) return;
    emit(current.copyWith(
      elapsedSeconds: event.seconds,
      timerPaused: event.paused,
    ));
    try {
      await recordDraftElapsed(current.id, event.seconds, paused: event.paused);
    } catch (e, s) {
      addError(e, s);
    }
  }

  /// Write-through. In-memory state stays authoritative: a failed write is
  /// logged, not surfaced, and the next mutation retries with a full snapshot.
  Future<void> _persist(WorkoutInProgressState s) async {
    if (s.isEditing) return;
    try {
      await saveDraft(WorkoutDraft(
        workout: _toWorkout(s, durationSeconds: s.elapsedSeconds),
        timerPaused: s.timerPaused,
      ));
    } catch (e, st) {
      addError(e, st);
    }
  }

  Future<void> _onDiscarded(
    WorkoutDiscarded event,
    Emitter<WorkoutState> emit,
  ) async {
    if (state is! WorkoutInProgressState) return;
    final current = state as WorkoutInProgressState;
    if (!current.isEditing) {
      try {
        await discardDraft(current.id);
      } catch (e, s) {
        addError(e, s);
      }
    }
    emit(const WorkoutInitialState());
  }

  Future<void> _onFinished(
    WorkoutFinished event,
    Emitter<WorkoutState> emit,
  ) async {
    if (state is! WorkoutInProgressState) return;
    final current = state as WorkoutInProgressState;
    final workout = _toWorkout(current, durationSeconds: event.durationSeconds);

    try {
      if (current.isEditing) {
        // An edit is not a training event: no streak side-effect.
        await updateWorkout(workout);
      } else {
        // Same id as the draft row → the upsert flips it to 'done' in one
        // statement; there is never a moment with both a draft and a copy.
        await saveWorkout(workout);
        await updateStreak();
      }
      emit(WorkoutCompleteState(workout: workout));
    } catch (e, s) {
      addError(e, s); // routes to AppBlocObserver.onError
      emit(WorkoutErrorState(
        message: 'Failed to save workout',
        exercises: current.exercises,
      ));
      // Return to the editable state so the user can remove the offending
      // set/exercise and retry (BUG-26).
      emit(current);
    }
  }

  Workout _toWorkout(WorkoutInProgressState s, {required int durationSeconds}) =>
      Workout(
        id: s.id,
        // An edit keeps its original date; a session is dated from its start.
        date: s.editing?.date ?? s.startedAt,
        durationSeconds: durationSeconds,
        exercises: s.exercises,
      );
}
