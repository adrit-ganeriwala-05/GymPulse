import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/presentation/screens/calendar_screen.dart';

import '../../helpers/fakes.dart';

/// table_calendar hands the screen UTC day instants; groupByDay keys by local
/// civil date. The screen translates between the two — that translation is
/// the one piece of logic here that domain tests cannot see.
void main() {
  testWidgets('tapping a workout day opens its detail; the day before is empty', (tester) async {
    final repo = FakeWorkoutRepo();
    await registerFakes(repo);
    final now = DateTime.now();
    // Yesterday, so the test never depends on which hour of today it runs.
    final day = DateTime(now.year, now.month, now.day - 1, 18, 30);
    repo.done['w1'] = sampleWorkout(date: day);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: CalendarScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Streak Calendar'), findsOneWidget);

    // If yesterday is in the previous month the grid shows it as an outside
    // day; tap the first matching cell either way.
    await tester.tap(find.text('${day.day}').first);
    await tester.pumpAndSettle();
    expect(find.text('Bench'), findsOneWidget, reason: 'workout listed under its local day');
    expect(find.textContaining('1 exercises'), findsOneWidget);
    await tester.tapAt(const Offset(200, 20)); // dismiss sheet
    await tester.pumpAndSettle();

    final dayBefore = DateTime(now.year, now.month, now.day - 2);
    await tester.tap(find.text('${dayBefore.day}').first);
    await tester.pumpAndSettle();
    expect(find.text('Bench'), findsNothing);
  });
}
