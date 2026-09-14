import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/entities/exercise.dart';
import '../../../domain/entities/workout.dart';
import '../../../domain/usecases/get_workouts.dart';
import '../../../domain/usecases/save_workout.dart';
import '../../../domain/usecases/update_streak.dart';
import 'workout_event.dart';
import 'workout_state.dart';

class WorkoutBloc extends Bloc<WorkoutEvent, WorkoutState> {
  final GetWorkouts getWorkouts;
  final SaveWorkout saveWorkout;
  final UpdateStreak updateStreak;

  WorkoutBloc({
    required this.getWorkouts,
    required this.saveWorkout,
    required this.updateStreak,
  }) : super(const WorkoutInitialState()) {
    on<WorkoutStarted>(_onStarted);
    on<ExerciseAdded>(_onExerciseAdded);
    on<SetLogged>(_onSetLogged);
    on<SetRemoved>(_onSetRemoved);
    on<ExerciseRemoved>(_onExerciseRemoved);
    on<WorkoutFinished>(_onFinished);
    on<HistoryRequested>(_onHistoryRequested);
  }

  void _onStarted(WorkoutStarted event, Emitter<WorkoutState> emit) {
    emit(const WorkoutInProgressState(exercises: []));
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

    emit(WorkoutInProgressState(exercises: exercises));
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
    emit(WorkoutInProgressState(exercises: exercises));
  }

  void _onExerciseRemoved(ExerciseRemoved event, Emitter<WorkoutState> emit) {
    if (state is! WorkoutInProgressState) return;
    final current = state as WorkoutInProgressState;
    emit(WorkoutInProgressState(
      exercises: current.exercises.where((e) => e.name != event.name).toList(),
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
      date: DateTime.now(),
      durationSeconds: event.durationSeconds,
      exercises: current.exercises,
    );

    // FIX: try/catch so save failures emit error state instead of crashing
    try {
      await saveWorkout(workout);
      await updateStreak();
      emit(WorkoutCompleteState(workout: workout));
    } catch (e) {
      emit(WorkoutErrorState(
        message: 'Failed to save workout',
        exercises: current.exercises,
      ));
      // Return to the editable state so the user can remove the offending
      // set/exercise and retry. Every mutation handler gates on
      // WorkoutInProgressState, so staying in the error state would lock them out.
      emit(WorkoutInProgressState(exercises: current.exercises));
    }
  }

  Future<void> _onHistoryRequested(
    HistoryRequested event,
    Emitter<WorkoutState> emit,
  ) async {
    final workouts = await getWorkouts();
    emit(WorkoutHistoryState(workouts: workouts));
  }
}
