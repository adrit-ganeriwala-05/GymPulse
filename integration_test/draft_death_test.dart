import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Process-death seed/resume script. NOTE: on Android `flutter test
/// integration_test/...` reinstalls the APK on EVERY run and wipes app data,
/// so this cannot prove persistence under the test harness (observed: run 2
/// still saw phase 1). The authoritative check is a real debug build driven
/// by adb (`am force-stop`, relaunch) — see FIXES.md round 3. Kept because
/// phase 1 alone still exercises the pause+checkpoint path on device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder labelled(String l) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == l);
  Future<void> settle(WidgetTester t, [int ms = 600]) async {
    await t.pump(Duration(milliseconds: ms));
    await t.pumpAndSettle();
  }
  int? timerSeconds(WidgetTester t) {
    final re = RegExp(r'^(\d\d):(\d\d)$');
    for (final w in t.widgetList<Text>(find.byType(Text))) {
      final m = re.firstMatch(w.data ?? '');
      if (m != null) return int.parse(m[1]!) * 60 + int.parse(m[2]!);
    }
    return null;
  }

  testWidgets('draft survives process death', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final phase2 = prefs.getBool('death_seeded') ?? false;
    debugPrint('DEATH-TEST phase=${phase2 ? 2 : 1}');

    if (!phase2) {
      await deleteDatabase(p.join(await getDatabasesPath(), 'gympulse.db'));
      await prefs.clear();
      await prefs.setBool('onboarding_complete', true);
      await prefs.setString('user_name', 'Adrit');
      app.main();
      await settle(tester, 1500);
      await tester.tap(find.text('Begin Workout 💪'));
      await settle(tester, 1000);
      await tester.tap(find.text('Add Exercise'));
      await settle(tester);
      await tester.enterText(labelled('Exercise name'), 'Bench');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      await tester.ensureVisible(find.text('Log Set'));
      await tester.tap(find.text('Log Set'));
      await settle(tester);
      await tester.enterText(labelled('Reps'), '10');
      await tester.enterText(labelled('kg'), '100');
      await tester.ensureVisible(find.byIcon(Icons.check_circle));
      await tester.tap(find.byIcon(Icons.check_circle));
      await settle(tester, 1200);
      await tester.tap(find.descendant(
          of: find.byType(BottomSheet), matching: find.byIcon(Icons.close)));
      await settle(tester, 800);
      await tester.pump(const Duration(seconds: 3));
      await tester.ensureVisible(find.text('Pause'));
      await tester.tap(find.text('Pause'));
      await settle(tester, 800);
      expect(find.text('Resume'), findsOneWidget, reason: 'timer paused');
      await tester.pump(const Duration(seconds: 1)); // checkpoint lands
      await prefs.setBool('death_seeded', true);
      return;
    }

    await prefs.remove('death_seeded');
    app.main();
    await settle(tester, 1500);
    expect(find.text('Workout in progress'), findsOneWidget, reason: 'draft survived kill');
    expect(find.text('Resume Workout ▶'), findsOneWidget);
    await tester.tap(find.text('Resume Workout ▶'));
    await settle(tester, 1000);
    expect(find.text('Bench'), findsOneWidget);
    expect(find.textContaining('10 reps'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget, reason: 'resumed PAUSED');
    expect(find.text('Pause'), findsNothing);
    final before = timerSeconds(tester);
    expect(before, isNotNull);
    expect(before!, inInclusiveRange(1, 60), reason: 'elapsed from draft, not wall clock');
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(timerSeconds(tester), before, reason: 'paused clock must not accrue');
  });
}
