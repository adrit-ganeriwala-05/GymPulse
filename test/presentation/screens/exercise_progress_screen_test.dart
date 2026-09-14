import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/presentation/screens/exercise_progress_screen.dart';
import 'package:gympulse/presentation/widgets/load_error_view.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeWorkoutRepo repo;
  late FakeProgressRepo progress;

  Future<void> pump(WidgetTester t, String name, {Map<String, Object> prefs = const {}}) async {
    await registerFakes(repo, prefs: prefs, progress: progress);
    await t.pumpWidget(MaterialApp(home: ExerciseProgressScreen(name: name)));
    await t.pumpAndSettle();
  }

  setUp(() {
    repo = FakeWorkoutRepo();
    progress = FakeProgressRepo(repo);
    repo.done['a'] = sampleWorkout(id: 'a', date: DateTime(2025, 6, 2, 18)); // Bench 10 × 60 kg
    repo.done['b'] = sampleWorkout(id: 'b', date: DateTime(2025, 6, 4, 18)); // same set → matches
  });

  testWidgets('PR chip on the earliest best day, "= PR" on a later equal day, newest first', (tester) async {
    await pump(tester, 'Bench');
    expect(find.text('Personal record'), findsOneWidget);
    expect(find.text('60 kg × 10'), findsNWidgets(3), reason: 'header + two day rows');
    expect(find.text('PR'), findsOneWidget);
    expect(find.text('= PR'), findsOneWidget);
    final prY = tester.getTopLeft(find.text('PR')).dy;
    final matchY = tester.getTopLeft(find.text('= PR')).dy;
    expect(matchY < prY, isTrue, reason: 'Jun 4 (match) is listed above Jun 2 (PR)');
    expect(find.textContaining('2 training days'), findsOneWidget);
  });

  testWidgets('stored kg render in the saved unit; the PR row does not move (BUG-01 in a new query)', (tester) async {
    await pump(tester, 'Bench', prefs: {'weight_unit': 'lbs'});
    expect(find.text('132.3 lbs × 10'), findsNWidgets(3));
    expect(find.text('60 kg × 10'), findsNothing);
    expect(find.text('PR'), findsOneWidget);
  });

  testWidgets('unknown exercise → empty state with the name as title', (tester) async {
    await pump(tester, ' Deadlift ');
    expect(find.text('Deadlift'), findsOneWidget);
    expect(find.textContaining('No finished workouts include'), findsOneWidget);
    expect(find.text('PR'), findsNothing);
  });

  testWidgets('read failure → LoadErrorView, Retry recovers', (tester) async {
    progress.failReads = true;
    await pump(tester, 'Bench');
    expect(find.byType(LoadErrorView), findsOneWidget);
    progress.failReads = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('PR'), findsOneWidget);
  });
}
