import '../repositories/streak_repository.dart';

class UpdateStreak {
  final StreakRepository repository;

  const UpdateStreak(this.repository);

  /// [on] is the civil day being credited; a finished draft passes its own
  /// start date so streak and calendar agree. Ignored for rest days.
  Future<void> call({bool isRestDay = false, DateTime? on}) async {
    if (isRestDay) {
      await repository.markRestDay();
    } else {
      await repository.updateStreak(on: on);
    }
  }
}
