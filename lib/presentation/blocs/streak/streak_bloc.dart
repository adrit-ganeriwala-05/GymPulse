import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/usecases/get_streak.dart';
import '../../../domain/usecases/update_streak.dart';
import 'streak_event.dart';
import 'streak_state.dart';

class StreakBloc extends Bloc<StreakEvent, StreakState> {
  final GetStreak getStreak;
  final UpdateStreak updateStreak;

  StreakBloc({required this.getStreak, required this.updateStreak})
      : super(const StreakInitialState()) {
    on<StreakLoaded>(_onLoaded);
    // bloc's default transformer is concurrent; both handlers below are
    // read-modify-write against SharedPreferences, so serialise them.
    on<StreakUpdated>(_onUpdated, transformer: sequential());
    on<RestDayMarked>(_onRestDayMarked, transformer: sequential());
  }

  Future<void> _onLoaded(StreakLoaded event, Emitter<StreakState> emit) async {
    final (streak, restDays) = await getStreak();
    emit(StreakLoadedState(currentStreak: streak, restDaysRemaining: restDays));
  }

  Future<void> _onUpdated(
    StreakUpdated event,
    Emitter<StreakState> emit,
  ) async {
    await updateStreak();
    final (streak, restDays) = await getStreak();
    emit(StreakLoadedState(currentStreak: streak, restDaysRemaining: restDays));
  }

  Future<void> _onRestDayMarked(
    RestDayMarked event,
    Emitter<StreakState> emit,
  ) async {
    await updateStreak(isRestDay: true);
    final (streak, restDays) = await getStreak();
    emit(StreakLoadedState(currentStreak: streak, restDaysRemaining: restDays));
  }
}
