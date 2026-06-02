import 'package:equatable/equatable.dart';

abstract class StreakEvent extends Equatable {
  const StreakEvent();

  @override
  List<Object?> get props => [];
}

class StreakLoaded extends StreakEvent {
  const StreakLoaded();
}

class StreakUpdated extends StreakEvent {
  const StreakUpdated();
}

class RestDayMarked extends StreakEvent {
  const RestDayMarked();
}
