import 'package:equatable/equatable.dart';

abstract class StreakState extends Equatable {
  const StreakState();

  @override
  List<Object?> get props => [];
}

class StreakInitialState extends StreakState {
  const StreakInitialState();
}

class StreakLoadedState extends StreakState {
  final int currentStreak;
  final int restDaysRemaining;

  const StreakLoadedState({
    required this.currentStreak,
    required this.restDaysRemaining,
  });

  @override
  List<Object?> get props => [currentStreak, restDaysRemaining];
}
