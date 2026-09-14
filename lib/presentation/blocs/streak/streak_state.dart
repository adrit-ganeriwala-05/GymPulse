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

  /// The datasource's own verdict on whether a rest day may be marked now —
  /// the UI shows the action iff this is true, so button and guard agree.
  final bool canRestToday;

  const StreakLoadedState({
    required this.currentStreak,
    required this.restDaysRemaining,
    this.canRestToday = false,
  });

  @override
  List<Object?> get props => [currentStreak, restDaysRemaining, canRestToday];
}
