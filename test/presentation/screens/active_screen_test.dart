import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/domain/entities/exercise.dart';
import 'package:gympulse/domain/entities/workout.dart';
import 'package:gympulse/presentation/blocs/workout/workout_event.dart';
import 'package:gympulse/presentation/screens/active_screen.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeWorkoutRepo repo;
  late FakeStreakRepo streak;

  Finder labelled(String l) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == l);

  Future<void> pumpActive(WidgetTester t, {double keyboard = 0}) async {
    // Phone-sized surface so the exercise section is on-screen and tappable.
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1.0;
    t.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(t.view.reset);
    await t.pumpWidget(activeScreenHarness(const ActiveScreen(), repo, streak));
    await t.pump(); // Loading
    await t.pump(const Duration(milliseconds: 50)); // draft lookup resolves
  }

  Future<void> addBench(WidgetTester t) async {
    await t.tap(find.text('Add Exercise'));
    await t.pump();
    await t.enterText(labelled('Exercise name'), 'Bench');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 50));
  }

  setUp(() { repo = FakeWorkoutRepo(); streak = FakeStreakRepo(); });

  testWidgets('shows a spinner while the draft lookup is in flight (Feature A)', (tester) async {
    repo.readGate = Completer<void>();
    await tester.pumpWidget(activeScreenHarness(const ActiveScreen(), repo, streak));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Tap "Add Exercise" to start logging'), findsNothing);
    repo.readGate!.complete();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Tap "Add Exercise" to start logging'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Finish FAB is hidden while the keyboard is up (device bug #2)', (tester) async {
    await pumpActive(tester, keyboard: 300);
    expect(find.text('Finish Workout ✓'), findsNothing);
    await pumpActive(tester);
    expect(find.text('Finish Workout ✓'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('log set → rest sheet lays out with a bounded Start button (device bug #3)', (tester) async {
    await pumpActive(tester);
    await addBench(tester);
    await tester.tap(find.text('Log Set'));
    await tester.pump();
    await tester.enterText(labelled('Reps'), '10');
    await tester.enterText(labelled('kg'), '100');
    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pump(); // post-frame opens the sheet
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Rest Timer'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no infinite-width constraint');
    expect(repo.draft!.exercises.single.sets.single.weight, 100, reason: 'write-through');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('invalid set shows errorText and is not logged (BUG-02/23)', (tester) async {
    await pumpActive(tester);
    await addBench(tester);
    await tester.tap(find.text('Log Set'));
    await tester.pump();
    await tester.enterText(labelled('Reps'), '0');
    await tester.enterText(labelled('kg'), 'NaN');
    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pump();
    expect(find.text('Must be > 0'), findsOneWidget);
    expect(find.text('Enter a number'), findsOneWidget);
    expect(repo.draft!.exercises.single.sets, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('remove-set and remove-exercise affordances reach the bloc (BUG-26)', (tester) async {
    repo.draft = Workout(
      id: 'd', date: DateTime.now(), durationSeconds: 0,
      exercises: const [Exercise(name: 'Bench', sets: [ExerciseSet(reps: 10, weight: 60)])],
    );
    await pumpActive(tester);
    expect(find.textContaining('10 reps'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove set'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('10 reps'), findsNothing);
    await tester.tap(find.byTooltip('Remove exercise'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Bench'), findsNothing);
    expect(repo.draft!.exercises, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('edit mode starts with the clock paused at the saved duration', (tester) async {
    final saved = Workout(id: 'w', date: DateTime(2025, 5, 1), durationSeconds: 1500,
        exercises: const [Exercise(name: 'Row', sets: [])]);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(activeScreenHarness(const ActiveScreen(), repo, streak,
        start: WorkoutEditStarted(saved)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Edit Workout'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget, reason: 'not 25:03');
    expect(find.text('Resume'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resuming a paused draft shows Resume, not Pause (item 1)', (tester) async {
    repo.draft = Workout(id: 'd', date: DateTime.now(), durationSeconds: 754, exercises: const []);
    repo.draftPaused = true;
    await pumpActive(tester);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
    expect(find.text('12:34'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('12:34'), findsOneWidget, reason: 'paused clock does not accrue');
    await tester.pumpWidget(const SizedBox());
  });
}
