abstract class StreakRepository {
  Future<int> getStreak();
  Future<int> getRestDaysRemaining();
  Future<void> updateStreak();
  Future<void> markRestDay();
}
