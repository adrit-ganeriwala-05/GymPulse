import '../repositories/streak_repository.dart';

class UpdateStreak {
  final StreakRepository repository;

  const UpdateStreak(this.repository);

  Future<void> call({bool isRestDay = false}) async {
    if (isRestDay) {
      await repository.markRestDay();
    } else {
      await repository.updateStreak();
    }
  }
}
