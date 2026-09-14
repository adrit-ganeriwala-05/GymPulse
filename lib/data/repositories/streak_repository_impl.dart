import '../../domain/repositories/streak_repository.dart';
import '../datasources/streak_local_datasource.dart';

class StreakRepositoryImpl implements StreakRepository {
  final StreakLocalDatasource datasource;

  const StreakRepositoryImpl(this.datasource);

  @override
  Future<int> getStreak() => datasource.getStreak();

  @override
  Future<int> getRestDaysRemaining() => datasource.getRestDaysRemaining();

  @override
  Future<bool> canMarkRestDay() => datasource.canMarkRestDay();

  @override
  Future<void> updateStreak({DateTime? on}) => datasource.updateStreak(on: on);

  @override
  Future<void> markRestDay() => datasource.markRestDay();
}
