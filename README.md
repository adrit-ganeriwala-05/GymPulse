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

## Bugs we found, and how we fixed them

What the bug looked like to a user, then what we changed. Nothing counted as a bug
until we could reproduce it, and no fix counted as done until it ran on a real phone.

### Your data was wrong or at risk

- **Switching kg to lbs relabelled your history instead of converting it — a 100 kg lift suddenly read as 100 lbs.**  
  *Fix:* every weight is stored in kilograms and converted only when it's shown or typed, so flipping the switch changes the display and never the stored number.

- **One unparseable number in the weight field could lock an entire workout out of being saved, with no way back to correct it.**  
  *Fix:* input is validated for meaning as you type, and a failed save now returns you to your workout with buttons to remove the offending set and retry.

- **Deleting a workout left its exercises and sets behind in the database.**  
  *Fix:* the cleanup setting is applied at the one moment the database actually honours it, and a test proves deletes now cascade against a real database.

- **The next change to the database structure would have crashed or wiped every existing install.**  
  *Fix:* an upgrade path that applies each change in order, tested by building genuinely old database files and walking them forward with the data intact.

- **A workout started at 11:50 PM was filed under the next day, because the date was stamped when you pressed Finish.**  
  *Fix:* a workout is dated from when you started it, and the streak is credited to that same day.

### The streak was lying to you

- **Streaks broke once a year on the daylight-saving changeover, because that day is 23 hours long and the app measured elapsed hours instead of counting days.**  
  *Fix:* calendar days are counted directly, so a short day still counts as one — and the tests pretend to run in a daylight-saving timezone, verified to genuinely fail against the old code.

- **Workouts and rest days were recorded in the same place, so the app couldn't tell whether you'd already trained today.**  
  *Fix:* two separate records — days you trained, and days your streak stayed alive — so each question has its own answer.

- **Tapping "Mark Rest Day" twice quickly spent both of your weekly rest days at once.**  
  *Fix:* those actions queue and run one at a time, and the day is recorded before the count is reduced, so a double-tap can only ever count once.

- **Your weekly rest-day allowance reset on a drifting schedule — leave the app for eight days and you got an eight-day week.**  
  *Fix:* weeks run Monday to Sunday, taken from the calendar.

- **The "Mark Rest Day" button stayed on screen after you'd taken one, and tapping it silently did nothing.**  
  *Fix:* the button asks the rule itself whether the tap would work and hides when it wouldn't, so there's one source of truth instead of two.

### Timers, navigation, and things that only broke on a real phone

- **A phone call, a background app kill, or the back button lost everything you'd logged that session.**  
  *Fix:* the session is saved after every change, so Home can offer to resume it — stopwatch picking up where it stopped, not counting the hours you were away, and still paused if you'd paused it.

- **A failed save followed by a retry recorded your 25-minute workout as 0:00.**  
  *Fix:* the clock now reports its time whether running or paused, and saving doesn't stop it until the save has actually succeeded — the three features that each relied on the old behaviour were fine alone, and only broke together.

- **On Android, the back gesture quit the app mid-workout instead of returning to Home. iPhone never showed this.**  
  *Fix:* changed how screens are stacked, so the gesture returns you to Home with your session safely saved and a message saying so.

- **Onboarding text overflowed the screen, the Finish button covered the confirm tick, the rest timer opened as an empty dark panel, and tapping a workout card on Home did nothing.**  
  *Fix:* all four were invisible to automated tests and found by running the app on a phone — there's now a test that drives the real app end to end on both Android and iPhone.

- **The app downloaded its fonts from the internet on first launch, in an app built to work offline.**  
  *Fix:* the fonts ship inside the app.

### Things we checked that turned out to be fine

- **The first-launch guard was suspected of using a stale value.** It reads the current one correctly; no change needed.
- **The database reads less efficiently than it theoretically could.** At the scale one person generates it's imperceptible, so we left it and noted where the limit would be.
- **Editing a workout repeatedly was suspected of rounding your weights.** Stored values are identical to the last decimal after two round trips.
