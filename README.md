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

Each one is written as what a user would have seen, then what we changed. The rule
we worked to: a bug wasn't real until we could reproduce it, and a fix wasn't done
until we'd run it on a real phone.

### Your data was wrong or at risk

**Switching kg to lbs silently rewrote your history.**
You log a 100 kg bench press. Later you flip the unit switch to pounds. Every past
workout now says "100 lbs" — the same number with a different label stuck on it. A
100 kg lift had just been restated as roughly 45 kg. Flip it back and it says kg
again. Nothing was ever converted.
*Fix:* the app now stores every weight in kilograms, always, and converts only at
the moment something is shown on screen or typed in. The stored number never
changes when you flip the switch — only the label and the displayed value do.

**One bad number could lock an entire workout out of being saved.**
Typing something the app couldn't make sense of in the weight field produced a value
that the database refused to store. The save failed, and the screen that appeared
afterwards gave you no way to go back and correct the entry. The workout was stuck:
unable to save, unable to edit, gone as soon as you left.
*Fix:* input is checked for meaning, not just for "is this a number" — no zero or
negative reps, no impossible weights — and the error appears under the field as you
type. If a save does fail, you land back on your workout with buttons to delete the
offending set or exercise and try again.

**Deleting a workout left its exercises behind.**
The database was supposed to clean up a workout's exercises and sets automatically
when the workout was deleted. The setting that turns that behaviour on was being
applied at a moment when the database ignores it, so it never actually took effect.
Deleted workouts were leaving orphaned data behind, invisibly.
*Fix:* the setting is now applied every time the database is opened, at the one
point where it works. Deletes clean up after themselves, and a test proves it
against a real database rather than assuming it.

**The next app update would have wiped everyone's history.**
The database had no upgrade path written. The moment we changed its structure — which
any new feature would require — every existing install would have crashed on launch
or lost its data.
*Fix:* an upgrade path that applies each change in order, so someone updating from a
very old version gets every step applied one after another. Tests build genuinely old
database files and upgrade them, checking the workouts inside survive intact.

**A late-night workout was filed under the wrong day.**
Start at 11:50 PM, finish at 12:20 AM, and the workout was recorded as happening the
next day — because the date was stamped when you pressed Finish, not when you started.
*Fix:* a workout is dated from when you started it, and your streak is credited to
that same day.

### The streak was lying to you

**The streak broke once a year, on the day the clocks changed.**
The app worked out "did I train yesterday?" by measuring the time between two days and
dividing by 24 hours. On the spring clock change, a day is only 23 hours long. The
maths came out as "less than one day", the app decided yesterday was actually today,
and streaks broke for anyone training that weekend.
*Fix:* the app now counts calendar days directly instead of measuring elapsed hours,
so a short day still counts as one day. The tests for this deliberately pretend to run
in a timezone that has daylight saving, and we checked they genuinely fail against the
old code — a test for a timezone bug is worthless if it only runs somewhere without
one.

**Rest days and workouts were being recorded in the same place.**
The app kept a single note saying "something happened on this day" for both training
and rest. It therefore couldn't answer "have I already trained today?" — so it would
let you spend one of your two weekly rest days on a day you'd already been to the gym,
and let you claim a rest day before you had any streak to protect.
*Fix:* two separate records — one for the days you trained, one for the days your
streak stayed alive — so each question has an answer.

**Tapping "Mark Rest Day" twice quickly used up both of your rest days.**
Two taps in the same instant both read "2 remaining" before either had written its
result, so both wrote "1". One tap, two days gone.
*Fix:* those actions now queue up and run one at a time, and the underlying code
records the day first so even an unexpected double-tap can only count once.

**Your weekly rest days reset on a random day.**
The "week" was measured as the last seven days from whenever you'd last opened the
app, so it drifted. Leave the app for eight days and you got an eight-day week.
*Fix:* weeks run Monday to Sunday, from the calendar.

**The "Mark Rest Day" button sometimes did nothing.**
After taking a rest day, the button stayed on screen offering another one. Tapping it
had no effect, with no explanation — the button and the rule behind it were each
working off different information.
*Fix:* the button now asks the rule itself whether the tap would work, and hides
itself when it wouldn't. One source of truth instead of two.

### Timers, navigation, and things that only broke on a real phone

**Losing an in-progress workout.**
Answer a phone call, get distracted, or have the phone close the app in the
background, and everything you'd logged that session was gone. Pressing back did the
same thing.
*Fix:* the session is written to storage after every single change, so there's nothing
to lose — no matter how the app closes. Home offers to resume it, with the stopwatch
picking up at exactly the time it stopped at rather than counting the hours you were
away, and paused if it was paused.

**A failed save could record your workout as lasting zero minutes.**
The clock could only report its time while it was actively running; asked while paused,
it answered "zero". That didn't matter for years. Then three separate features started
relying on it: saving stopped the clock before writing to the database, editing an old
workout opened with the clock paused, and the auto-save recorded whatever the clock last
said. Put together: if a save failed and you retried, your 25-minute workout saved as
0:00.
*Fix:* the clock reports its time whether running or paused, and saving no longer stops
it until the save has actually succeeded — so a retry still has your real time. The
wider lesson, which is in our notes: the individual pieces were each fine and each
tested. Nobody had tested them *together*, because the assumption they shared had never
been written down.

**On Android, the back gesture quit the app mid-workout.**
Swiping back from an active session closed GymPulse entirely instead of returning to
Home. This never happened on iPhone, which has no system back gesture.
*Fix:* a change to how screens are stacked, so the gesture returns you to Home and your
session is safely saved as a draft, with a message telling you so.

**Things that only a real device revealed.** Text overflowing off the bottom of the
onboarding screens while the keyboard was sliding away; the Finish button floating up
and covering the confirm tick when the keyboard opened; the rest timer sheet appearing
as an empty dark panel; tapping a workout card on Home doing nothing at all. None of
these could be seen in automated tests — they were all found by running the app on a
phone, which is why there's now a test that drives the real app end to end on both
Android and iPhone.

**The app fetched its fonts from the internet on first launch** — in an app whose whole
premise is working offline. On a plane or with no signal, the text rendered in a fallback
font.
*Fix:* the fonts ship inside the app.

### Things we checked that turned out to be fine

Not every suspicion was real. The first-launch screen's guard was correct as written.
The database reads more slowly than it theoretically could, but at the scale one person
generates — a few hundred workouts — it's imperceptible, so we left it alone and noted
where the limit is. And editing a workout repeatedly does not gradually round your
weights: we checked the stored numbers are identical, to the last decimal, after two
round trips.
