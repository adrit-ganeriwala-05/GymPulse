import '../repositories/streak_repository.dart';

class GetStreak {
  final StreakRepository repository;

  const GetStreak(this.repository);

  Future<(int streak, int restDaysRemaining, bool canRestToday)> call() async {
    final streak = await repository.getStreak();
    final restDays = await repository.getRestDaysRemaining();
    final canRest = await repository.canMarkRestDay();
    return (streak, restDays, canRest);
  }
}
