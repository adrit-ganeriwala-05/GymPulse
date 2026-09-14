import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/data/repositories/settings_repository_impl.dart';
import 'package:gympulse/domain/usecases/get_weight_unit.dart';
import 'package:gympulse/domain/usecases/save_weight_unit.dart';
import 'package:gympulse/presentation/blocs/settings/settings_bloc.dart';
import 'package:gympulse/presentation/blocs/settings/settings_event.dart';
import 'package:gympulse/presentation/blocs/settings/settings_state.dart';
import 'package:gympulse/presentation/units.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('units', () {
    test('display <-> kg round-trips without drift (BUG-01)', () {
      for (final kg in [0.0, 2.5, 61.2349, 100.0, 227.5]) {
        expect(displayToKg(kgToDisplay(kg, kUnitLbs), kUnitLbs), closeTo(kg, 1e-9));
        expect(displayToKg(kgToDisplay(kg, kUnitKg), kUnitKg), kg);
      }
    });

    test('formatWeight rounds for display only', () {
      expect(formatWeight(100, kUnitKg), '100');
      expect(formatWeight(61.2349, kUnitKg), '61.2');
      expect(formatWeight(100, kUnitLbs), '220.5');
      expect(formatWeight(1000, kUnitLbs, decimals: 0), '2205');
    });
  });

  group('SettingsBloc + SettingsRepositoryImpl', () {
    test('defaults to kg, persists a change, emits it', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = SettingsRepositoryImpl(prefs);
      final bloc = SettingsBloc(
        getWeightUnit: GetWeightUnit(repo),
        saveWeightUnit: SaveWeightUnit(repo),
      );
      bloc.add(const SettingsLoaded());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, const SettingsLoadedState('kg'));
      bloc.add(const WeightUnitChanged('lbs'));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, const SettingsLoadedState('lbs'));
      expect(prefs.getString('weight_unit'), 'lbs');
      await bloc.close();
    });
  });
}
