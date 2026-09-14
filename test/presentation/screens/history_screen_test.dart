import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/presentation/screens/history_screen.dart';
import 'package:gympulse/presentation/widgets/load_error_view.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeWorkoutRepo repo;
  setUp(() async { repo = FakeWorkoutRepo(); await registerFakes(repo); });

  testWidgets('DB failure renders LoadErrorView, and Retry recovers (BUG-11)', (tester) async {
    repo.failReads = true;
    await tester.pumpWidget(const MaterialApp(home: HistoryScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(LoadErrorView), findsOneWidget);
    expect(find.text('No workouts yet'), findsNothing, reason: 'error must not look empty');
    repo.failReads = false;
    repo.done['w1'] = sampleWorkout();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(LoadErrorView), findsNothing);
    expect(find.textContaining('1 exercises'), findsOneWidget);
  });

  testWidgets('long-press → Delete → confirm deletes and reloads (Feature B)', (tester) async {
    repo.done['w1'] = sampleWorkout();
    await tester.pumpWidget(const MaterialApp(home: HistoryScreen()));
    await tester.pumpAndSettle();
    await tester.longPress(find.textContaining('1 exercises'));
    await tester.pumpAndSettle();
    expect(find.text('Edit workout'), findsOneWidget);
    await tester.tap(find.text('Delete workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(repo.deleted, ['w1']);
    expect(find.text('No workouts yet'), findsOneWidget);
  });
}
