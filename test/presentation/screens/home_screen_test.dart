import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gympulse/data/datasources/streak_local_datasource.dart';
import 'package:gympulse/data/repositories/streak_repository_impl.dart';
import 'package:gympulse/domain/usecases/get_streak.dart';
import 'package:gympulse/domain/usecases/update_streak.dart';
import 'package:gympulse/presentation/blocs/streak/streak_bloc.dart';
import 'package:gympulse/presentation/blocs/streak/streak_event.dart';
import 'package:gympulse/presentation/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeWorkoutRepo repo;
  late FakeStreakRepo streak;
  setUp(() async {
    repo = FakeWorkoutRepo();
    streak = FakeStreakRepo();
    await registerFakes(repo, prefs: {'user_name': 'Adrit'});
  });

  testWidgets('waits before rendering the empty state (BUG-11 flash)', (tester) async {
    repo.readGate = Completer<void>();
    await tester.pumpWidget(homeHarness(const HomeScreen(), streak));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No workouts yet.\nStart your first!'), findsNothing);
    repo.readGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('No workouts yet.\nStart your first!'), findsOneWidget);
    expect(find.textContaining('Welcome, Adrit'), findsOneWidget);
  });

  testWidgets('trained today → Mark Rest Day hidden; tile says Longest run (BUG-07/09)', (tester) async {
    repo.done['w1'] = sampleWorkout();
    streak.streak = 1;
    await tester.pumpWidget(homeHarness(const HomeScreen(), streak));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mark Rest Day'), findsNothing);
    expect(find.text('Longest run'), findsOneWidget);
    expect(find.text('Best Streak'), findsNothing);
    expect(find.text('View all'), findsOneWidget);
  });

  testWidgets('no workout today and a live streak → Mark Rest Day shown', (tester) async {
    repo.done['w1'] = sampleWorkout(date: DateTime.now().subtract(const Duration(days: 1)));
    streak.streak = 1;
    streak.canRest = true;
    await tester.pumpWidget(homeHarness(const HomeScreen(), streak));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mark Rest Day'), findsOneWidget);
  });

  testWidgets('open draft → banner with age and Discard; CTA says Resume (Feature A)', (tester) async {
    repo.draft = sampleWorkout(id: 'd', date: DateTime.now().subtract(const Duration(days: 3)), duration: 754);
    await tester.pumpWidget(homeHarness(const HomeScreen(), streak));
    await tester.pumpAndSettle();
    expect(find.text('Workout in progress'), findsOneWidget);
    expect(find.textContaining('3 days ago'), findsOneWidget);
    expect(find.textContaining('12:34 active'), findsOneWidget);
    expect(find.text('Resume Workout ▶'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(repo.deleted, ['d']);
    expect(find.text('Begin Workout 💪'), findsOneWidget);
  });

  testWidgets('Mark Rest Day disappears once a rest day is marked; button and guard agree (AUDIT2-02)', (tester) async {
    // Real streak datasource: the fake cannot express "already rested today".
    final today = DateTime(2025, 6, 3, 9);
    final yesterday = DateTime(2025, 6, 2);
    await registerFakes(repo, prefs: {
      'streak_count': 1,
      'last_workout_date': yesterday.toIso8601String(),
      'last_streak_day': yesterday.toIso8601String(),
    });
    final ds = StreakLocalDatasourceImpl(locator<SharedPreferences>(), clock: () => today);
    final streakRepo = StreakRepositoryImpl(ds);
    await tester.pumpWidget(MaterialApp(
      home: BlocProvider(
        create: (_) => StreakBloc(
          getStreak: GetStreak(streakRepo),
          updateStreak: UpdateStreak(streakRepo),
        )..add(const StreakLoaded()),
        child: const HomeScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mark Rest Day (2 left'), findsOneWidget);
    await tester.tap(find.textContaining('Mark Rest Day'));
    await tester.pumpAndSettle();
    expect(await ds.getRestDaysRemaining(), 1);
    expect(find.textContaining('Mark Rest Day'), findsNothing,
        reason: 'datasource refuses a second rest today, so the button must not offer it');
  });
}
