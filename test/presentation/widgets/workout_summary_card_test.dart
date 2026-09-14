import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/presentation/widgets/workout_summary_card.dart';

import '../../helpers/fakes.dart';

void main() {
  testWidgets('onTap wins: tap navigates, does not expand (device bug #4)', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WorkoutSummaryCard(workout: sampleWorkout(), onTap: () => taps++)),
    ));
    await tester.tap(find.byType(WorkoutSummaryCard));
    await tester.pump();
    expect(taps, 1);
    expect(find.textContaining('total volume'), findsNothing, reason: 'not expanded');
  });

  testWidgets('without onTap a tap expands and shows converted weights', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WorkoutSummaryCard(workout: sampleWorkout(), weightUnit: 'lbs')),
    ));
    await tester.tap(find.byType(WorkoutSummaryCard));
    await tester.pump();
    expect(find.textContaining('total volume'), findsOneWidget);
    // 60 kg stored → 132.3 lbs shown; storage untouched (BUG-01).
    expect(find.textContaining('132.3 lbs'), findsOneWidget);
  });
}
