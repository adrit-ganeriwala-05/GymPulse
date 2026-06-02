abstract class SettingsRepository {
  Future<String> getWeightUnit();
  Future<void> saveWeightUnit(String unit);
}
