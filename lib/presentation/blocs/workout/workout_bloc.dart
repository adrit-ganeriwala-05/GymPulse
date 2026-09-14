import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/entities/exercise.dart';
import '../../../domain/entities/workout.dart';
import '../../../domain/usecases/save_workout.dart';
import '../../../domain/usecases/update_streak.dart';
import 'workout_event.dart';
import 'workout_state.dart';

class WorkoutBloc extends Bloc<WorkoutEvent, WorkoutState> {
  final SaveWorkout saveWorkout;
  final UpdateStreak updateStreak;

  /// Injectable clock; stamps [WorkoutInProgressState.startedAt].
  final DateTime Function() now;

  WorkoutBloc({
    required this.saveWorkout,
    required this.updateStreak,
    DateTime Function()? clock,
  })  : now = clock ?? DateTime.now,
        super(const WorkoutInitialState()) {
    on<WorkoutStarted>(_onStarted);
    on<ExerciseAdded>(_onExerciseAdded);
    on<SetLogged>(_onSetLogged);
    on<SetRemoved>(_onSetRemoved);
    on<ExerciseRemoved>(_onExerciseRemoved);
    on<WorkoutFinished>(_onFinished);
  }

  void _onStarted(WorkoutStarted event, Emitter<WorkoutState> emit) {
    emit(WorkoutInProgressState(exercises: const [], startedAt: now()));
  }

  void _onExerciseAdded(ExerciseAdded event, Emitter<WorkoutState> emit) {
    if (state is! WorkoutInProgressState) return;
    final current = state as WorkoutInProgressState;
    final alreadyExists = current.exercises.any((e) => e.name == event.name);
    if (alreadyExists) return;
    emit(WorkoutInProgressState(
      exercises: [
        ...current.exercises,
        Exercise(name: event.name, sets: const []),
      ],
      startedAt: current.startedAt,
    ));
  }

  void _onSetLogged(SetLogged event, Emitter<WorkoutState> emit) {
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

    emit(WorkoutInProgressState(exercises: exercises, startedAt: current.startedAt));
  }

  void _onSetRemoved(SetRemoved event, Emitter<WorkoutState> emit) {
    if (state is! WorkoutInProgressState) return;
    final current = state as WorkoutInProgressState;
    final exercises = current.exercises.map((e) {
      if (e.name != event.exerciseName) return e;
      if (event.setIndex < 0 || event.setIndex >= e.sets.length) return e;
      final sets = List<ExerciseSet>.from(e.sets)..removeAt(event.setIndex);
      return Exercise(name: e.name, sets: sets);
    }).toList();
    emit(WorkoutInProgressState(exercises: exercises, startedAt: current.startedAt));
  }

  void _onExerciseRemoved(ExerciseRemoved event, Emitter<WorkoutState> emit) {
    if (state is! WorkoutInProgressState) return;
    final current = state as WorkoutInProgressState;
    emit(WorkoutInProgressState(
      exercises: current.exercises.where((e) => e.name != event.name).toList(),
      startedAt: current.startedAt,
    ));
  }

  Future<void> _onFinished(
    WorkoutFinished event,
    Emitter<WorkoutState> emit,
  ) async {
    if (state is! WorkoutInProgressState) return;
    final current = state as WorkoutInProgressState;
    final workout = Workout(
      id: const Uuid().v4(),
      date: current.startedAt,
      durationSeconds: event.durationSeconds,
      exercises: current.exercises,
    );

    // FIX: try/catch so save failures emit error state instead of crashing
    try {
      await saveWorkout(workout);
      await updateStreak();
      emit(WorkoutCompleteState(workout: workout));
    } catch (e, s) {
      addError(e, s); // routes to AppBlocObserver.onError
      emit(WorkoutErrorState(
        message: 'Failed to save workout',
        exercises: current.exercises,
      ));
      // Return to the editable state so the user can remove the offending
      // set/exercise and retry. Every mutation handler gates on
      // WorkoutInProgressState, so staying in the error state would lock them out.
      emit(WorkoutInProgressState(
        exercises: current.exercises,
        startedAt: current.startedAt,
      ));
    }
  }
}
