import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/presentation/router.dart';

import '../helpers/fakes.dart';

/// Real GoRouter on top of the fakes: pins the redirect from a fresh install
/// and the round-3 routing fix (system back from /active reaches PopScope and
/// Home refreshes via RouteObserver) in-process, not only on a device.
void main() {
  late FakeWorkoutRepo repo;
  late FakeStreakRepo streak;

  Finder labelled(String l) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == l);

  Future<void> pumpApp(WidgetTester t, {required bool onboarded}) async {
    // 600 wide: the Ahem test font is ~2x wider than the bundled faces, so a
    // phone width overflows Home's title rows here but not on a device.
    t.view.physicalSize = const Size(600, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await registerFakes(repo, prefs: {
      if (onboarded) 'onboarding_complete': true,
      'user_name': 'Adrit',
    });
    registerBlocFactories(repo, streak);
    await t.pumpWidget(MaterialApp.router(routerConfig: createRouter(onboarded)));
    await t.pumpAndSettle();
  }

  setUp(() {
    repo = FakeWorkoutRepo();
    streak = FakeStreakRepo();
  });

  testWidgets('fresh install: every location redirects to onboarding', (tester) async {
    await pumpApp(tester, onboarded: false);
    expect(find.text('Welcome to GymPulse'), findsOneWidget);
    for (final loc in ['/', '/active', '/history', '/calendar']) {
      GoRouterHelper(tester).go(loc);
      await tester.pumpAndSettle();
      expect(find.text('Welcome to GymPulse'), findsOneWidget, reason: loc);
    }
    // Completing onboarding lands on Home and stays there.
    await tester.enterText(find.byType(TextField), 'Adrit');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Welcome, Adrit'), findsOneWidget);
  });

  testWidgets('system back from /active reaches PopScope; Home refreshes with the draft banner', (tester) async {
    await pumpApp(tester, onboarded: true);
    expect(find.text('Begin Workout 💪'), findsOneWidget);
    await tester.tap(find.text('Begin Workout 💪'));
    await tester.pumpAndSettle();
    expect(find.text('Active Workout'), findsOneWidget);
    await tester.tap(find.text('Add Exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(labelled('Exercise name'), 'Bench');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.draft!.exercises.single.name, 'Bench');

    // The OS back gesture, as the embedder delivers it.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Saved as draft — resume from Home'), findsOneWidget);
    expect(find.text('Workout in progress'), findsOneWidget,
        reason: 'didPopNext must reload the draft banner');
    expect(find.text('Resume Workout ▶'), findsOneWidget);
    expect(find.text('Active Workout'), findsNothing, reason: 'app did not exit, /active popped');
  });

  testWidgets('finishing a workout returns to Home with the new workout listed', (tester) async {
    await pumpApp(tester, onboarded: true);
    await tester.tap(find.text('Begin Workout 💪'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(labelled('Exercise name'), 'Bench');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish Workout ✓'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save & Finish'));
    await tester.pumpAndSettle();
    expect(find.text('Begin Workout 💪'), findsOneWidget, reason: 'draft consumed');
    expect(find.textContaining('1 exercises'), findsOneWidget,
        reason: 'Home reloaded its workouts on didPopNext');
    expect(streak.updates, 1);
  });
}

/// Minimal go-to helper: reach the router through the widget tree.
extension GoRouterHelper on WidgetTester {
  void go(String location) {
    final router = (widget<MaterialApp>(find.byType(MaterialApp)).routerConfig)!;
    (router as dynamic).go(location);
  }
}
