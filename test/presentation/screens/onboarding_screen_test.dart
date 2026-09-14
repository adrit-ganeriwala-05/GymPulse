import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/presentation/screens/onboarding_screen.dart';

import '../../helpers/fakes.dart';

void main() {
  testWidgets('pages 2/3 do not overflow at keyboard height (device bug #1)', (tester) async {
    await registerFakes(FakeWorkoutRepo());
    // Phone with the keyboard up: the body is ~260 px tall.
    tester.view.physicalSize = const Size(402, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await tester.enterText(find.byType(TextField), 'Adrit');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Build Your Streak'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Time Every Rep'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty name is rejected and the PageView cannot be swiped (BUG-15)', (tester) async {
    await registerFakes(FakeWorkoutRepo());
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Please enter your name'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to GymPulse'), findsOneWidget, reason: 'still on page 1');
  });
}
