abstract class StreakRepository {
  Future<int> getStreak();
  Future<int> getRestDaysRemaining();
  Future<bool> canMarkRestDay();

  /// Credits the training day [on] (default: today).
  Future<void> updateStreak({DateTime? on});
  Future<void> markRestDay();
}
