import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/usecases/get_weight_unit.dart';
import '../../../domain/usecases/save_weight_unit.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final GetWeightUnit _getWeightUnit;
  final SaveWeightUnit _saveWeightUnit;

  SettingsBloc({
    required GetWeightUnit getWeightUnit,
    required SaveWeightUnit saveWeightUnit,
  })  : _getWeightUnit = getWeightUnit,
        _saveWeightUnit = saveWeightUnit,
        super(const SettingsInitialState()) {
    on<SettingsLoaded>(_onLoaded);
    on<WeightUnitChanged>(_onUnitChanged);
  }

  Future<void> _onLoaded(
    SettingsLoaded event,
    Emitter<SettingsState> emit,
  ) async {
    final unit = await _getWeightUnit();
    emit(SettingsLoadedState(unit));
  }

  Future<void> _onUnitChanged(
    WeightUnitChanged event,
    Emitter<SettingsState> emit,
  ) async {
    await _saveWeightUnit(event.unit);
    emit(SettingsLoadedState(event.unit));
  }
}
