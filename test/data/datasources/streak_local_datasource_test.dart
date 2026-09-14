import 'package:flutter_test/flutter_test.dart';
import 'package:gympulse/data/datasources/streak_local_datasource.dart';
import 'package:gympulse/domain/streak_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late DateTime clock;
  late StreakLocalDatasourceImpl ds;

  // Mon 2025-06-02 is a Monday; chosen so week-boundary cases are legible.
  final monday = DateTime(2025, 6, 2);
  DateTime day(int offset) => DateTime(monday.year, monday.month, monday.day + offset);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    clock = monday;
    ds = StreakLocalDatasourceImpl(prefs, clock: () => clock);
  });

  group('civil date helpers', () {
    test('civilDaysBetween is DST-safe on the spring-forward pair', () {
      // US DST: Mar 9 2025 02:00 -> 03:00. Two local midnights are 23h apart,
      // so Duration.inDays would report 0. In a non-DST test TZ the pair is
      // simply 24h apart; the assertion holds either way.
      expect(civilDaysBetween(DateTime(2025, 3, 9), DateTime(2025, 3, 10)), 1);
      expect(civilDaysBetween(DateTime(2025, 11, 2), DateTime(2025, 11, 3)), 1);
    });

    test('startOfWeek returns Monday for every weekday, across a month edge', () {
      for (var i = 0; i < 7; i++) {
        expect(startOfWeek(day(i)), monday, reason: 'offset $i');
      }
      // Sun 2025-03-02 -> Mon 2025-02-24 (crosses into February).
      expect(startOfWeek(DateTime(2025, 3, 2)), DateTime(2025, 2, 24));
    });
  });

  group('updateStreak', () {
    test('first workout starts streak at 1', () async {
      await ds.updateStreak();
      expect(await ds.getStreak(), 1);
    });

    test('consecutive days increment', () async {
      await ds.updateStreak();
      clock = day(1);
      await ds.updateStreak();
      clock = day(2);
      await ds.updateStreak();
      expect(await ds.getStreak(), 3);
    });

    test('gap of exactly one day (trained yesterday) increments', () async {
      await ds.updateStreak();
      clock = day(1);
      await ds.updateStreak();
      expect(await ds.getStreak(), 2);
    });

    test('gap > 1 resets to 1', () async {
      await ds.updateStreak();
      clock = day(1);
      await ds.updateStreak();
      clock = day(3); // skipped day(2)
      await ds.updateStreak();
      expect(await ds.getStreak(), 1);
    });

    test('same-day double workout counts once', () async {
      await ds.updateStreak();
      await ds.updateStreak();
      expect(await ds.getStreak(), 1);
    });

    test('gap of exactly one day is still alive (morning before training)', () async {
      await ds.updateStreak();
      clock = day(1);
      await ds.updateStreak();
      clock = day(2); // not trained yet today
      expect(await ds.getStreak(), 2);
    });

    test('getStreak never writes: a lapsed read leaves prefs untouched', () async {
      await ds.updateStreak();
      clock = day(1);
      await ds.updateStreak();
      final before = {for (final k in prefs.getKeys()) k: prefs.get(k)};
      clock = day(5);
      expect(await ds.getStreak(), 0);
      expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, before);
      expect(prefs.getInt('streak_count'), 2, reason: 'updateStreak owns the write');
    });

    test('lapsed streak reads as 0 until the next workout', () async {
      await ds.updateStreak();
      clock = day(1);
      await ds.updateStreak();
      clock = day(4);
      expect(await ds.getStreak(), 0);
    });

    test('DST spring-forward pair increments (BUG-03)', () async {
      clock = DateTime(2025, 3, 9);
      await ds.updateStreak();
      clock = DateTime(2025, 3, 10);
      await ds.updateStreak();
      expect(await ds.getStreak(), 2);
    });

    test('legacy install: last_workout_date alone seeds continuity', () async {
      // Pre-split installs wrote only last_workout_date.
      SharedPreferences.setMockInitialValues({
        'streak_count': 4,
        'last_workout_date': day(0).toIso8601String(),
      });
      prefs = await SharedPreferences.getInstance();
      ds = StreakLocalDatasourceImpl(prefs, clock: () => clock);
      clock = day(1);
      await ds.updateStreak();
      expect(await ds.getStreak(), 5);
    });
  });

  group('updateStreak(on:) — a finished draft credits its own day (A2-03)', () {
    test('yesterday\'s draft finished today: last workout = yesterday, alive today', () async {
      clock = day(1);
      await ds.updateStreak(on: day(0));
      expect(prefs.getString('last_workout_date'), day(0).toIso8601String());
      expect(await ds.getStreak(), 1);
      expect(await ds.canMarkRestDay(), isTrue, reason: 'did not train today');
    });

    test('backdated day chains onto the streak (gap 1 as of that day)', () async {
      await ds.updateStreak(); // Mon
      clock = day(2); // Wed: finish Tuesday\'s draft
      await ds.updateStreak(on: day(1));
      expect(await ds.getStreak(), 2);
      expect(prefs.getString('last_streak_day'), day(1).toIso8601String());
    });

    test('backdated workout inside a rest-bridged chain: +1, continuity marker not moved back', () async {
      // The only way "rest today, then finish yesterday's draft" is reachable:
      // the streak must already be alive today, i.e. bridged by rest days.
      await ds.updateStreak(); // Mon train
      clock = day(1);
      await ds.markRestDay(); // Tue rest (alive: gap 1 from Mon)
      clock = day(2);
      await ds.markRestDay(); // Wed rest (alive: gap 1 from Tue)
      await ds.updateStreak(on: day(1)); // then finish Tuesday's draft
      expect(await ds.getStreak(), 2, reason: 'Mon, Tue trained; Wed rested');
      expect(prefs.getString('last_workout_date'), day(1).toIso8601String());
      expect(prefs.getString('last_streak_day'), day(2).toIso8601String());
      expect(await ds.getRestDaysRemaining(), 0, reason: 'tokens stay burned');
    });

    test('backdated behind an already-credited day is history, not a streak day', () async {
      await ds.updateStreak(); // Mon
      clock = day(1);
      await ds.updateStreak(); // Tue
      await ds.updateStreak(on: day(0)); // Monday\'s second draft
      expect(await ds.getStreak(), 2);
      expect(prefs.getString('last_workout_date'), day(1).toIso8601String());
    });

    test('a stale draft from before a lapse restarts at 1 and reads 0 today', () async {
      await ds.updateStreak(); // Mon
      clock = day(6); // Sun: finish Thursday\'s draft (gap 3 from Mon)
      await ds.updateStreak(on: day(3));
      expect(prefs.getInt('streak_count'), 1);
      expect(await ds.getStreak(), 0, reason: 'Thu -> Sun is a gap of 3');
    });
  });

  group('canMarkRestDay mirrors markRestDay\'s guard (A2-02)', () {
    test('false with no streak; true the day after training; false once rested', () async {
      expect(await ds.canMarkRestDay(), isFalse);
      await ds.updateStreak();
      expect(await ds.canMarkRestDay(), isFalse, reason: 'trained today');
      clock = day(1);
      expect(await ds.canMarkRestDay(), isTrue);
      await ds.markRestDay();
      expect(await ds.canMarkRestDay(), isFalse, reason: 'already rested today');
      clock = day(2);
      expect(await ds.canMarkRestDay(), isTrue);
      await ds.markRestDay();
      clock = day(3);
      expect(await ds.canMarkRestDay(), isFalse, reason: 'no tokens left this week');
      clock = day(5);
      expect(await ds.canMarkRestDay(), isFalse, reason: 'lapsed');
    });
  });

  group('markRestDay', () {
    test('rest day bridges the streak without incrementing it', () async {
      await ds.updateStreak(); // Mon
      clock = day(1);
      await ds.markRestDay(); // Tue
      expect(await ds.getStreak(), 1);
      expect(await ds.getRestDaysRemaining(), kRestDaysPerWeek - 1);
      clock = day(2);
      await ds.updateStreak(); // Wed
      expect(await ds.getStreak(), 2);
    });

    test('cannot rest on a day already trained (BUG-07)', () async {
      await ds.updateStreak();
      await ds.markRestDay();
      expect(await ds.getRestDaysRemaining(), kRestDaysPerWeek);
    });

    test('cannot rest before any streak exists (BUG-10)', () async {
      await ds.markRestDay();
      expect(await ds.getRestDaysRemaining(), kRestDaysPerWeek);
      expect(await ds.getStreak(), 0);
    });

    test('cannot rest after the streak has lapsed', () async {
      await ds.updateStreak();
      clock = day(3);
      await ds.markRestDay();
      expect(await ds.getRestDaysRemaining(), kRestDaysPerWeek);
    });

    test('marking twice on one day consumes one token (BUG-08)', () async {
      await ds.updateStreak();
      clock = day(1);
      await Future.wait([ds.markRestDay(), ds.markRestDay()]);
      expect(await ds.getRestDaysRemaining(), kRestDaysPerWeek - 1);
    });

    test('rest then workout on the same day counts the workout', () async {
      await ds.updateStreak();
      clock = day(1);
      await ds.markRestDay();
      await ds.updateStreak();
      expect(await ds.getStreak(), 2);
    });

    test('rest day does not touch last_workout_date', () async {
      await ds.updateStreak();
      clock = day(1);
      await ds.markRestDay();
      expect(prefs.getString('last_workout_date'), day(0).toIso8601String());
    });
  });

  group('weekly allowance (ISO week, BUG-18/19/22)', () {
    Future<void> burnOne() async {
      await ds.updateStreak();
      clock = clock.add(const Duration(hours: 25)); // next civil day
      clock = civilDate(clock);
      await ds.markRestDay();
    }

    test('6 days later: same week, allowance not reset', () async {
      await burnOne(); // Mon train, Tue rest -> 1 left
      clock = day(6); // Sunday
      expect(await ds.getRestDaysRemaining(), kRestDaysPerWeek - 1);
    });

    test('7 days later: new week, allowance reset', () async {
      await burnOne();
      clock = day(7); // next Monday
      expect(await ds.getRestDaysRemaining(), kRestDaysPerWeek);
    });

    test('8 days later: reset, anchored to Monday not to today', () async {
      await burnOne();
      clock = day(8); // next Tuesday
      expect(await ds.getRestDaysRemaining(), kRestDaysPerWeek);
      expect(prefs.getString('week_start_date'), day(7).toIso8601String());
    });

    test('unused tokens do not carry over', () async {
      await ds.updateStreak();
      clock = day(7);
      expect(await ds.getRestDaysRemaining(), kRestDaysPerWeek);
    });
  });
}
