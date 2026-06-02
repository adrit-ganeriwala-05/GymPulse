import 'package:equatable/equatable.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

class SettingsLoaded extends SettingsEvent {
  const SettingsLoaded();
}

class WeightUnitChanged extends SettingsEvent {
  final String unit;

  const WeightUnitChanged(this.unit);

  @override
  List<Object?> get props => [unit];
}
