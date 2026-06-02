import 'package:equatable/equatable.dart';

abstract class SettingsState extends Equatable {
  const SettingsState();

  @override
  List<Object?> get props => [];
}

class SettingsInitialState extends SettingsState {
  const SettingsInitialState();
}

class SettingsLoadedState extends SettingsState {
  final String weightUnit;

  const SettingsLoadedState(this.weightUnit);

  @override
  List<Object?> get props => [weightUnit];
}
