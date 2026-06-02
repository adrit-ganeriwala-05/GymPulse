import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SharedPreferences _prefs;

  static const _unitKey = 'weight_unit';

  const SettingsRepositoryImpl(this._prefs);

  @override
  Future<String> getWeightUnit() async =>
      _prefs.getString(_unitKey) ?? 'kg';

  @override
  Future<void> saveWeightUnit(String unit) async =>
      _prefs.setString(_unitKey, unit);
}
