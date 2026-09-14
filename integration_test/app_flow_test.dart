import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/main.dart' as app;
import 'package:gympulse/presentation/widgets/workout_summary_card.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Drives the real app on a device/simulator through the core flow, starting
/// from a pre-seeded **v1** database so the whole v1→v4 ladder (including the
/// v4 table rebuild) is exercised on the real sqflite plugin, not only under
/// ffi.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> seedV1Database() async {
    final path = p.join(await getDatabasesPath(), 'gympulse.db');
    await deleteDatabase(path);
    final v1 = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('CREATE TABLE workouts (id TEXT PRIMARY KEY, date TEXT NOT NULL, duration_seconds INTEGER NOT NULL DEFAULT 0)');
      await db.execute('CREATE TABLE exercises (id TEXT PRIMARY KEY, workout_id TEXT NOT NULL, name TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (workout_id) REFERENCES workouts(id) ON DELETE CASCADE)');
      await db.execute('CREATE TABLE sets (id TEXT PRIMARY KEY, exercise_id TEXT NOT NULL, reps INTEGER NOT NULL, weight REAL NOT NULL, position INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE)');
    });
    await v1.insert('workouts', {'id': 'legacy', 'date': '2025-01-05T10:00:00.000', 'duration_seconds': 5400});
    await v1.insert('exercises', {'id': 'e1', 'workout_id': 'legacy', 'name': 'Legacy Row', 'position': 0});
    await v1.insert('sets', {'id': 's1', 'exercise_id': 'e1', 'reps': 12, 'weight': 40.0, 'position': 0});
    await v1.close();
  }

  Finder labelled(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label);

  Future<void> settle(WidgetTester t, [int ms = 600]) async {
    await t.pump(Duration(milliseconds: ms));
    await t.pumpAndSettle();
  }

  testWidgets('core flow on a migrated v1 database', (tester) async {
    await seedV1Database();
    (await SharedPreferences.getInstance()).clear();

    app.main();
    await settle(tester, 1500);

    // ---- onboarding: swipe is disabled, buttons are the only gate ----
    expect(find.text('Welcome to GymPulse'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await settle(tester);
    expect(find.text('Please enter your name'), findsOneWidget, reason: 'empty name rejected');
    await tester.enterText(find.byType(TextField), 'Adrit');
    await tester.tap(find.text('Next'));
    await settle(tester);
    await tester.tap(find.text('Next'));
    await settle(tester);
    await tester.tap(find.text('Get Started'));
    await settle(tester, 1000);

    // ---- home: migrated legacy workout visible, streak 0, no rest button ----
    expect(find.textContaining('Welcome, Adrit'), findsOneWidget);
    expect(find.text('Recent Activity'), findsOneWidget);
    expect(find.textContaining('1 exercises'), findsWidgets, reason: 'legacy row survived migration');
    expect(find.textContaining('Mark Rest Day'), findsNothing, reason: 'no streak yet');

    // ---- start workout ----
    await tester.tap(find.text('Begin Workout 💪'));
    await settle(tester, 1000);
    expect(find.text('Active Workout'), findsOneWidget);
    await tester.tap(find.text('Add Exercise'));
    await settle(tester);
    await tester.enterText(labelled('Exercise name'), 'Bench');
    await tester.testTextInput.receiveAction(TextInputAction.done); // onSubmitted → _submit
    await settle(tester);
    expect(find.text('Bench'), findsOneWidget);

    // ---- validation: 0 reps rejected with visible error ----
    await tester.ensureVisible(find.text('Log Set'));
    await tester.tap(find.text('Log Set'));
    await settle(tester);
    await tester.enterText(labelled('Reps'), '0');
    await tester.enterText(labelled('kg'), '100');
    await tester.ensureVisible(find.byIcon(Icons.check_circle));
    await tester.tap(find.byIcon(Icons.check_circle));
    await settle(tester);
    expect(find.text('Must be > 0'), findsOneWidget);

    // ---- log a valid set → rest sheet opens ----
    await tester.enterText(labelled('Reps'), '10');
    await tester.ensureVisible(find.byIcon(Icons.check_circle));
    await tester.tap(find.byIcon(Icons.check_circle));
    await settle(tester, 1200);
    expect(find.text('Rest Timer'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(BottomSheet), matching: find.byIcon(Icons.close)));
    await settle(tester, 800);
    expect(find.textContaining('10 reps'), findsOneWidget);

    // ---- remove the set, then log another ----
    await tester.tap(find.byTooltip('Remove set'));
    await settle(tester);
    expect(find.textContaining('10 reps'), findsNothing);
    await tester.ensureVisible(find.text('Log Set'));
    await tester.tap(find.text('Log Set'));
    await settle(tester);
    await tester.enterText(labelled('Reps'), '8');
    await tester.enterText(labelled('kg'), '60');
    await tester.ensureVisible(find.byIcon(Icons.check_circle));
    await tester.tap(find.byIcon(Icons.check_circle));
    await settle(tester, 1200);
    await tester.tap(find.descendant(
        of: find.byType(BottomSheet), matching: find.byIcon(Icons.close)));
    await settle(tester, 800);
    expect(find.textContaining('8 reps'), findsOneWidget);

    // ---- finish ----
    await tester.tap(find.text('Finish Workout ✓'));
    await settle(tester);
    await tester.tap(find.text('Save & Finish'));
    await settle(tester, 1500);

    // ---- home after save: streak 1, rest button hidden (trained today) ----
    expect(find.text('Recent Activity'), findsOneWidget);
    expect(find.text('current streak'), findsOneWidget);
    expect(find.textContaining('Mark Rest Day'), findsNothing,
        reason: 'BUG-07: cannot rest on a day already trained');
    expect(find.text('Longest run'), findsOneWidget);

    // ---- calendar ----
    await tester.tap(find.byIcon(Icons.calendar_month));
    await settle(tester, 1000);
    expect(find.text('Streak Calendar'), findsOneWidget);
    expect(find.text('Rest day'), findsNothing, reason: 'phantom legend removed');
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await settle(tester, 800);

    // ---- history: legacy + new, delete legacy via long-press ----
    // Card tap navigates (InkWell owns the tap now); View all also exists.
    expect(find.text('View all'), findsOneWidget);
    await tester.ensureVisible(find.textContaining('1 exercises').first);
    await tester.tap(find.textContaining('1 exercises').first);
    await settle(tester, 1000);
    expect(find.text('Workout History'), findsOneWidget);
    expect(find.textContaining('Jan 5'), findsOneWidget, reason: 'legacy row');
    await tester.longPress(find.textContaining('Jan 5'));
    await settle(tester);
    await tester.tap(find.text('Delete workout'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester, 1000);
    expect(find.textContaining('Jan 5'), findsNothing, reason: 'cascade delete');

    // ---- exercise progress (Feature D): expand the card, tap the name ----
    await tester.tap(find.byType(WorkoutSummaryCard).first);
    await settle(tester);
    await tester.ensureVisible(find.text('Bench'));
    await tester.tap(find.text('Bench'));
    await settle(tester, 1000);
    expect(find.text('Personal record'), findsOneWidget);
    expect(find.text('60 kg × 8'), findsWidgets, reason: 'aggregate read on the real plugin, kg as stored');
    expect(find.text('PR'), findsOneWidget);
    await tester.pageBack();
    await settle(tester, 800);
    expect(find.text('Workout History'), findsOneWidget);

    // ---- edit: opens active screen in edit mode; back asks to confirm ----
    await tester.longPress(find.textContaining('1 exercises').first);
    await settle(tester);
    await tester.tap(find.text('Edit workout'));
    await settle(tester, 1000);
    expect(find.text('Edit Workout'), findsOneWidget);
    expect(find.text('Bench'), findsOneWidget);
  });
}
