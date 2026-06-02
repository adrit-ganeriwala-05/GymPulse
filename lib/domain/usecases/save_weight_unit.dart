import '../repositories/settings_repository.dart';

class SaveWeightUnit {
  final SettingsRepository repository;

  const SaveWeightUnit(this.repository);

  Future<void> call(String unit) => repository.saveWeightUnit(unit);
}
