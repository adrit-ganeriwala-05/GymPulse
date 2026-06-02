import '../repositories/settings_repository.dart';

class GetWeightUnit {
  final SettingsRepository repository;

  const GetWeightUnit(this.repository);

  Future<String> call() => repository.getWeightUnit();
}
