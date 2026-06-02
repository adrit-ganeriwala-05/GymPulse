import 'package:equatable/equatable.dart';

abstract class WorkoutEvent extends Equatable {
  const WorkoutEvent();

  @override
  List<Object?> get props => [];
}

class WorkoutStarted extends WorkoutEvent {
  const WorkoutStarted();
}

class ExerciseAdded extends WorkoutEvent {
  final String name;

  const ExerciseAdded(this.name);

  @override
  List<Object?> get props => [name];
}

class SetLogged extends WorkoutEvent {
  final String exerciseName;
  final int reps;
  final double weight;

  const SetLogged({
    required this.exerciseName,
    required this.reps,
    required this.weight,
  });

  @override
  List<Object?> get props => [exerciseName, reps, weight];
}

// FIX: named param so callsites are explicit about durationSeconds
class WorkoutFinished extends WorkoutEvent {
  final int durationSeconds;

  const WorkoutFinished({required this.durationSeconds});

  @override
  List<Object?> get props => [durationSeconds];
}

class HistoryRequested extends WorkoutEvent {
  const HistoryRequested();
}
