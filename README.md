# GymPulse

A clean, minimal workout tracking app built with Flutter.

## Features

- **Workout logging** — create and track workouts with exercises, sets, reps, and weight
- **Active workout session** — live workout timer, rest timer between sets, and exercise log
- **Draft persistence** — an in-progress session is saved on every change and survives backgrounding, navigation and process death; resume it from Home with the stopwatch exactly where it was
- **Edit and delete** — long-press any workout in History to edit it in place or delete it
- **Streak tracking** — daily workout streak with two rest-day tokens per week
- **Workout history** — browse past workouts with summary cards
- **Calendar view** — visualize workout days on a monthly calendar
- **Weight unit settings** — toggle between kg and lbs; everything is stored in kg and converted only for display
- **Onboarding** — first-launch setup flow

## Tech Stack

- **Flutter** + **Dart**
- **flutter_bloc** — state management
- **get_it** — dependency injection
- **go_router** — navigation
- **sqlite** — local SQLite database
- **shared_preferences** — lightweight persistent storage
- **table_calendar** — calendar widget
- **google_fonts** — Playfair Display + DM Sans typography

## Architecture

Clean Architecture with three layers:

```
lib/
├── data/           # Models, datasources, repository implementations
├── domain/         # Entities, repository interfaces, use cases
└── presentation/   # Screens, widgets, BLoCs
```

## Platforms

Android, iOS, macOS. (Web/Windows/Linux scaffolds were removed: sqflite has
no implementation there and the app cannot persist anything.)

## Getting Started

**Prerequisites:** Flutter SDK 3.x, Dart SDK ^3.11.4

```bash
git clone "https://github.com/adrit-ganeriwala-05/GymPulse"
cd gympulse
flutter pub get
flutter run
```

## Testing

```bash
flutter analyze                                   # zero issues
flutter test                                      # 106 unit + widget tests
flutter test integration_test/app_flow_test.dart -d <device>   # full flow on a device, from a seeded v1 database
```

The unit suite runs the real datasource against real SQLite (`sqflite_common_ffi`), the timer BLoCs under `fakeAsync`, and every screen with real BLoCs over in-memory repositories. The integration test seeds a schema-v1 database first so every run also exercises the migration ladder on the real plugin. Process death is checked by hand on Android with `adb shell am force-stop` — the integration harness reinstalls the APK on every run, which wipes app data, so it cannot prove persistence on its own.

## Bugs we found, and how we tackled them

The app went through several audit-and-fix rounds. The rule was: no bug is real until it has a failing test or a device reproduction, and no fix is done until it has been executed on both platforms. These are the ones worth knowing about.

### Data

- **Weight unit relabelled history instead of converting it.** Toggling kg → lbs changed the suffix on every stored number and nothing else, so a 100 kg bench read as 100 lbs. Fix: storage is always kilograms; conversion happens in one place (`presentation/units.dart`) at parse time and at render time. Round-trip and edit tests pin that stored values never pass through display rounding.
- **`NaN` and `Infinity` passed validation.** `double.tryParse` accepts them; SQLite turns `NaN` into `NULL`, which violates `NOT NULL` and made the whole workout permanently unsaveable — and the error state had no way back. Fix: validate meaning, not parse success (`isFinite`, `> 0`, sanity caps) with inline error text, and let the user remove the offending set or exercise and retry.
- **`PRAGMA foreign_keys = ON` was a silent no-op.** It ran inside `onCreate`, which sqflite wraps in a transaction, and the pragma is ignored in a transaction. Cascades never fired. Fix: the pragma lives in `onConfigure`, the only hook that runs on every open, outside the transaction. The draft feature now relies on that cascade deliberately (`INSERT OR REPLACE` on the parent row cleanly recreates its children).
- **Schema `version: 1` with no `onUpgrade`.** Any future bump would have thrown and bricked every existing install. Fix: a forward-only ladder (`if (oldVersion < N)`), an explicit downgrade policy, and migration tests that build real v1 and v2 files and walk them up — the v2 → v3 case guards against the classic mistake of re-running an `ALTER TABLE` that already happened.
- **Workout dated at finish, not start.** A session crossing midnight was filed under the wrong day. Fix: the date is captured when the session starts, and the streak is credited to that same day.

### Streak logic

- **DST broke consecutive days.** `difference().inDays` divides elapsed time by 24 h; two local midnights across spring-forward are 23 h apart, so "yesterday" read as "today". Truncating to midnight does not help — the *distance* is wrong, not the operands. Fix: project both dates onto UTC before subtracting. The tests set `TZ=America/New_York` inside the process and were run against the old arithmetic to confirm they actually fail — a DST test that inherits the host's zone proves nothing on a UTC machine.
- **One preference key meant two things.** `last_workout_date` was written by both workouts and rest days, so "did I train today?" could not be asked, a rest token could be burned on a day already trained, and a rest day could be marked before any streak existed. Fix: separate `last_workout_date` (training only) from `last_streak_day` (continuity), with the semantics written down in one place.
- **Rest-day marking raced.** bloc's default event transformer is concurrent, so two taps in one frame both read "2 left" and both wrote "1". Fix: `sequential()` on read-modify-write handlers, and the datasource writes its same-day guard first so an unserialised caller still cannot double-decrement.
- **The weekly allowance never aligned to a week.** A rolling 7-day window re-anchored to "today", so an 8-day gap produced an 8-day week. Fix: ISO Monday weeks derived from the calendar.
- **Two definitions of "can I rest today".** The Home button and the datasource guard used different data sources, so the button stayed after a rest day and did nothing when tapped. Fix: the datasource exposes its own verdict and the button shows exactly when a tap would succeed.

### Concurrency and lifecycle

- **A latent timer bug surfaced by three unrelated features.** `Stop` and `Pause` read the elapsed seconds only from the *running* state; from a paused clock they returned 0. Harmless since the first commit, until save-failure recovery stopped the clock before saving, edit mode seeded the clock paused, and the draft checkpoint persisted whatever `Stop` emitted. Result: a retried save after a disk error stored `duration 0`. Fix: read from running or paused, ignore a redundant pause, and never stop the clock before the save is known to have succeeded. The lesson we took: name the invariant ("Stop is only sent to a running clock") and test the interaction, not just the parts.
- **System back on Android exited the app mid-workout.** go_router's `popRoute` bypasses `PopScope` on a root route. Fix: `/active` is a child route of `/`, so the gesture reaches the Navigator; Home stays alive underneath and refreshes through a `RouteObserver`. iOS never surfaced this because it has no system back.
- **Database open could cache a failure.** The `database` getter is now a single-flight future that is cleared when the open fails, so one bad open does not poison every later call. (The "two concurrent opens" worry that motivated it turned out to be unfounded — sqflite already single-instances and serialises opens per path — and the test that claimed to prove it was replaced with one for the failure branch.)
- **`FlutterError.onError` was replaced instead of chained**, which broke every test binding. Fix: chain the previous handler.

### UI found only on a device

- Onboarding pages overflowed while the keyboard from page one was still animating away; the finish button floated up over the ✓ on the set-entry row; the rest-timer sheet's Start button inherited an infinite-width theme constraint and never painted; a tap on a Home card lost the gesture arena to the card's own `InkWell`. All four were invisible to unit tests and caught by driving the real app on a simulator — which is why the integration suite exists.
- **Fonts fetched over the network on first launch**, contradicting the offline-first claim, and a missing weight failed silently. Fix: bundle the fonts and disable runtime fetching so a missing face fails loudly.

### Things that turned out not to be bugs

A few items on the original list were checked and cleared: the router's onboarding guard reads the flag live (no stale capture), the N+1 read path is fine at a solo user's volume (revisit past ~2,000 workouts), and edit mode carries stored weights through untouched (verified bit-identical after two edits).

