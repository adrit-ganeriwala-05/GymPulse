# GymPulse — Project Context

> Sole onboarding document for AI instances. Read this before touching code. Reflects the codebase **after** the Phase 2 fix series and the two Phase 3 features (see `FIXES.md`, `WALKTHROUGH.md`). §8 lists what the original version of this document got wrong. Treat it as a map, not truth: verify against source.

---

## 1. Project Overview

**GymPulse** is a single-user, offline-first Flutter app (Android, iOS, macOS) for tracking gym workouts. It has no backend, no auth, no network calls — everything persists locally on-device via SQLite (`sqflite`) and `shared_preferences`.

Primary use case: a solo gym-goer opens the app, starts a workout session, adds exercises, logs sets (reps × weight) as they go, times their rest between sets, finishes the workout (which is saved to local SQLite), and tracks a daily workout **streak** with a limited weekly rest-day allowance. Secondary flows: browsing workout history, viewing a monthly calendar of workout days, and toggling the displayed weight unit (kg/lbs).

There is no multi-user support, no cloud sync, and no export. Past workouts **can** be edited and deleted (long-press in History). An in-progress workout is persisted as a **draft** on every mutation and resumed on the next visit to `/active`.

---

## 2. Tech Stack & Dependencies

**Language / SDK**
- Dart SDK `^3.11.4`
- Flutter `3.41.6` (stable channel, installed toolchain)
- Package name: `gympulse`, version `1.0.0+1`, `publish_to: none`

**Runtime dependencies** (`pubspec.yaml`, resolved versions from `pubspec.lock` in parentheses)

| Package | Constraint | Resolved | Purpose |
|---|---|---|---|
| `flutter_bloc` | ^8.1.3 | 8.1.6 | State management (BLoC pattern) |
| `get_it` | ^7.6.4 | 7.7.0 | Service locator / dependency injection |
| `go_router` | ^13.2.0 | 13.2.5 | Declarative routing, guards |
| `equatable` | ^2.0.5 | 2.0.8 | Value equality for BLoC events/states |
| `shared_preferences` | ^2.2.2 | 2.5.5 | Key-value persistence (settings, streak, onboarding flag) |
| `uuid` | ^4.3.3 | 4.5.3 | Generates workout/exercise/set IDs (v4) |
| `table_calendar` | ^3.0.9 | 3.2.0 | Month-view calendar widget |
| `bloc_concurrency` | ^0.2.5 | 0.2.5 | `sequential()` transformer for read-modify-write handlers |
| `google_fonts` | ^6.1.0 | 6.3.3 | Playfair Display + DM Sans typography |
| `sqflite` | ^2.3.2 | 2.4.2+1 | Local SQLite database for workout history |
| `path` | ^1.9.0 | 1.9.1 | Joins DB file path (`sqflite` helper) |

**Dev dependencies**
- `flutter_test` (SDK)
- `flutter_lints` ^6.0.0 — default rules. `flutter analyze` reports **zero issues**.
- `sqflite_common_ffi` — runs the real datasource against real SQLite in unit tests.
- `integration_test` (SDK) — `integration_test/app_flow_test.dart` drives the full flow on a simulator from a seeded v1 database.

**Platforms**: Android, iOS, macOS. `web/`, `windows/`, `linux/` were removed — sqflite has no implementation there.

**No backend, no HTTP client, no state persistence library beyond the two above.** No CI/CD config exists in the `gympulse/` project itself.

---

## 3. Architecture & Folder Structure

### 3.1 Pattern

Textbook **Clean Architecture**, three layers, one-way dependency rule (`presentation → domain ← data`):

- **`domain/`** — pure Dart, zero Flutter/package imports except within data models. Entities, repository *interfaces*, use cases. This is the innermost layer; nothing here depends on `data/` or `presentation/`.
- **`data/`** — implements domain repository interfaces. Contains datasources (talk to `sqflite` / `shared_preferences`) and models (entity subclasses with (de)serialization).
- **`presentation/`** — Flutter UI. BLoCs (state containers), screens, reusable widgets, and the router.

Composition root is `injection_container.dart`, using **`get_it`** as a service locator (not `provider`/Riverpod). All cross-cutting wiring happens there, once, at app startup (see §6.1).

### 3.2 Directory Tree

```
gympulse/
├── lib/
│   ├── main.dart                          # entrypoint, DI init, MaterialApp.router + full custom theme
│   ├── injection_container.dart           # get_it registrations (the composition root)
│   ├── domain/
│   │   ├── streak_rules.dart               # kRestDaysPerWeek, civilDate, civilDaysBetween, startOfWeek (pure Dart)
│   │   ├── workout_stats.dart              # countThisWeek/Month, longestRun, groupByDay, mostRecentDay (pure Dart)
│   │   ├── entities/
│   │   │   ├── exercise.dart              # Exercise, ExerciseSet (weight is ALWAYS kg)
│   │   │   └── workout.dart                # Workout
│   │   ├── repositories/                   # abstract interfaces only
│   │   │   ├── settings_repository.dart
│   │   │   ├── streak_repository.dart
│   │   │   └── workout_repository.dart
│   │   └── usecases/                       # thin call-wrappers, one class per operation
│   │       ├── get_streak.dart             # returns a Dart record (int, int)
│   │       ├── get_weight_unit.dart
│   │       ├── get_workouts.dart
│   │       ├── save_weight_unit.dart
│   │       ├── save_workout.dart           # new or finalised draft (caller bumps streak)
│   │       ├── update_workout.dart         # in-place edit (no streak side-effect)
│   │       ├── save_draft.dart / get_draft.dart / discard_draft.dart / record_draft_elapsed.dart
│   │       ├── delete_workout.dart
│   │       └── update_streak.dart
│   ├── data/
│   │   ├── datasources/
│   │   │   ├── workout_database.dart       # single-flight open, onConfigure FK pragma, v2 schema + onUpgrade ladder
│   │   │   ├── workout_local_datasource.dart   # upsertWorkout(status), getWorkouts (done), getDraft, deleteWorkout
│   │   │   └── streak_local_datasource.dart    # injectable clock; civil-date streak logic
│   │   ├── models/
│   │   │   ├── exercise_model.dart         # fromEntity only (JSON codec deleted)
│   │   │   └── workout_model.dart
│   │   └── repositories/                   # implement domain interfaces, delegate to datasources
│   │       ├── settings_repository_impl.dart
│   │       ├── streak_repository_impl.dart
│   │       └── workout_repository_impl.dart
│   └── presentation/
│       ├── app_bloc_observer.dart          # logs bloc errors via dart:developer
│       ├── format.dart                     # formatDuration (h:mm:ss), formatDayMonth
│       ├── units.dart                      # kg <-> display unit conversion at the render/parse boundary
│       ├── router.dart                     # GoRouter config; /active reads `extra` as a Workout to edit
│       ├── blocs/
│       │   ├── workout/                    # active session state machine
│       │   ├── workout_timer/              # elapsed-time stopwatch
│       │   ├── rest_timer/                 # countdown between sets
│       │   ├── streak/                     # daily streak + rest days
│       │   └── settings/                   # weight unit (kg/lbs)
│       ├── screens/
│       │   ├── onboarding_screen.dart
│       │   ├── home_screen.dart
│       │   ├── active_screen.dart
│       │   ├── history_screen.dart
│       │   └── calendar_screen.dart
│       └── widgets/
│           ├── circular_timer.dart         # CustomPainter arc gauge — used by both timers
│           ├── exercise_log_card.dart      # log/remove sets, remove exercise, validated input
│           ├── load_error_view.dart        # FutureBuilder error branch with retry
│           └── workout_summary_card.dart   # used on HomeScreen + HistoryScreen
├── test/
│   ├── data/datasources/streak_local_datasource_test.dart   # 21 cases, injected clock
│   ├── data/datasources/workout_local_datasource_test.dart  # real SQLite via ffi, incl. v1→v2 migration
│   └── presentation/blocs/workout_bloc_test.dart            # draft / resume / finish / edit / failure
├── integration_test/app_flow_test.dart     # on-device core flow from a seeded v1 DB
├── pubspec.yaml / pubspec.lock
├── analysis_options.yaml                   # default flutter_lints, no custom rules
└── android/ ios/ macos/                    # standard flutter create scaffolds, unmodified
```

### 3.3 Data Flow & State Management

- **Global/DI state**: `get_it` (`sl`) holds true singletons — the `SharedPreferences` instance, both repositories, both datasources, and all six use cases. These are constructed once in `init()` (`main.dart` awaits this before `runApp`).
- **Screen-scoped state**: BLoCs are registered as `registerFactory` in DI (a **new instance per resolution**), and each `GoRoute` builder wraps its screen in a `MultiBlocProvider` that resolves fresh BLoC instances and immediately dispatches a "load" event (e.g. `StreakLoaded()`, `WorkoutStarted()`). This means BLoC state does **not** survive navigating away and back — e.g. leaving `/active` and returning starts a brand-new `WorkoutBloc` with empty state (there is no draft/resume-workout feature).
- **Local ephemeral state**: individual screens/widgets use plain `StatefulWidget` + `setState` for form/UI-only concerns (onboarding page index, add-exercise form toggle, card expand/collapse, rest-timer duration picker). This is intentional — it's not business state.
- **Persistence flow** for a completed workout:
  `ActiveScreen (_FinishButton)` → `WorkoutBloc.add(WorkoutFinished)` → builds a `Workout` entity with a fresh UUID → `SaveWorkout` usecase → `WorkoutRepositoryImpl` → wraps in `WorkoutModel.fromEntity` → `WorkoutLocalDatasourceImpl.saveWorkout` → single `sqflite` transaction inserting into `workouts`, `exercises`, `sets` tables → on success also calls `UpdateStreak` usecase → `StreakRepositoryImpl` → `StreakLocalDatasourceImpl` (SharedPreferences) → emits `WorkoutCompleteState` → listener navigates to `/`.
- **Reads**: `HomeScreen`, `HistoryScreen`, and `CalendarScreen` each independently call `sl<GetWorkouts>()` directly inside `initState`/`didChangeDependencies` and render via `FutureBuilder` — they do **not** go through `WorkoutBloc` (even though `WorkoutBloc` has a `HistoryRequested` event / `WorkoutHistoryState` that is never dispatched from any screen — see §7). This is a duplication of read paths, not a shared single source of truth.
- Weight unit is read in two different ways across the app: reactively via `BlocBuilder<SettingsBloc, SettingsState>` (on `ActiveScreen`) and synchronously/non-reactively via `sl<SharedPreferences>().getString('weight_unit')` (on `HomeScreen`, `HistoryScreen`, `CalendarScreen`'s detail sheet). Both read the same underlying pref key so they stay consistent, but only the `SettingsBloc`-driven UI updates live without a rebuild trigger.

---

## 4. Core Features & Functionalities

### 4.1 Onboarding (`onboarding_screen.dart`)
- 3-page `PageView`: (1) name entry + welcome, (2) streak/rest-day explainer, (3) timer explainer.
- Page 1 requires a non-empty name (`_nameError` inline validation) before advancing; name is saved to `SharedPreferences['user_name']` immediately on "Next".
- Final page's "Get Started" button sets `SharedPreferences['onboarding_complete'] = true` and navigates to `/`.
- Enforced app-wide by a `GoRouter.redirect` guard in `router.dart`: any route other than `/onboarding` redirects back there if the flag isn't set. `main.dart` also picks `initialLocation` based on the same flag at boot.

### 4.2 Home (`home_screen.dart`)
- Greeting: `"Welcome, {name} 👋"` (name pulled from prefs in `initState`) + formatted current date.
- Streak card (`BlocBuilder<StreakBloc>`, loaded via `StreakLoaded()` in `didChangeDependencies`): shows fire emoji + `currentStreak`, rest-days-remaining, a weekly progress bar (`thisWeek / 5` clamped), and a "Mark Rest Day (N left)" button (only shown while `restDays > 0`) that dispatches `RestDayMarked()`.
- Three stat tiles computed **client-side** from the full workout list each build: `thisMonth` (count in current calendar month/year), `thisWeek` (rolling 7-day window, `diff < 7`, not calendar-week-aligned), and `bestStreak` (recomputed by scanning sorted workout dates for the longest run of consecutive days — **independent of** the persisted `StreakBloc` streak counter; see §7 for the discrepancy this creates).
- "Begin Workout 💪" CTA → `context.go('/active')`.
- "Recent Activity": shows every workout logged on the single most-recent workout day (not full history), tapping any card routes to `/history`.
- Calendar icon in the AppBar → `/calendar`.

### 4.3 Active Workout Session (`active_screen.dart`)
This is the most complex screen, composed of three cooperating BLoCs (`WorkoutBloc`, `WorkoutTimerBloc`, `RestTimerBloc`) plus `SettingsBloc`.

- **Workout timer**: `CircularTimer` gauge (progress capped visually at 3600s), Start/Pause/Stop/Resume/Reset button row driven by `WorkoutTimerState` variants.
- **Weight unit toggle**: pill button top-right of the exercise section, flips `kg`↔`lbs` via `SettingsBloc.add(WeightUnitChanged(...))`, persisted immediately.
- **Add Exercise**: inline expanding form (`TextField` + Cancel/Add), blocks case-insensitive duplicate names both at the BLoC level (`_onExerciseAdded` silently no-ops on dupes) and at the UI level (a `SnackBar` warns on submit if a dupe is typed).
- **Log a set**: each added exercise renders as an `ExerciseLogCard` (expandable, own reps/weight `TextField`s, "Log Set" toggle). Submitting a valid set dispatches `SetLogged` to `WorkoutBloc`, then **automatically opens a rest-timer bottom sheet** (`_showRestTimerSheet`).
  - The rest-timer sheet has documented workarounds for two real Flutter layout bugs: (a) the keyboard is force-dismissed and the sheet is deferred to `addPostFrameCallback` to avoid a `!_debugDoingThisLayout` assertion from opening a bottom sheet while the keyboard is still animating closed; (b) `Navigator.pop()` on timer-finished is likewise deferred a frame for the same reason.
  - Sheet offers 30/60/90/120s presets plus a custom-seconds `TextField`, Start/Pause/Resume, Reset, and Close. On natural completion (`RestTimerFinishedState`) it auto-closes and shows a "Rest complete! Time to work 💪" `SnackBar` 300ms later. Whatever closes the sheet (drag-dismiss, X, back gesture, natural finish) always dispatches `RestTimerReset()` in `.whenComplete()` to guarantee the periodic stream subscription is torn down.
- **Finish Workout**: floating button → two-step confirm (`Keep Going` / `Save & Finish`) rendered by swapping the FAB's content in place. Guards: blocks finishing with zero exercises (`SnackBar`, does not reach the confirm step); warns (but does not block) if the workout timer was never started, noting duration will record as 0:00. On confirm, stops the timer, reads its elapsed seconds, dispatches `WorkoutFinished(durationSeconds: ...)`. A `BlocListener<WorkoutBloc>` navigates to `/` on `WorkoutCompleteState` or shows an error `SnackBar` (and un-confirms) on `WorkoutErrorState`.

### 4.4 History (`history_screen.dart`)
- One-shot `FutureBuilder` over `GetWorkouts()`, fetched once in `initState`. The router gives this route a `UniqueKey()` on every navigation (`router.dart`), so navigating to `/history` always remounts the screen and refetches — but there is no pull-to-refresh or reactive update if data changes while the screen is alive.
- Empty state: emoji + "No workouts yet" + CTA to `/active`.
- Populated state: `ListView.builder` of `WorkoutSummaryCard`s. Data source (`WorkoutLocalDatasourceImpl.getWorkouts`) already returns rows `ORDER BY date DESC`, so the screen renders them as-is (comment in code explicitly warns against reversing).

### 4.5 Calendar (`calendar_screen.dart`)
- `table_calendar` month view, `firstDay: 2020-01-01`, `lastDay: 2030-12-31`, future dates disabled (`enabledDayPredicate`).
- Workouts are grouped by day (`Map<DateTime, List<Workout>>`) once the future resolves; a small dot marker renders under any day with ≥1 workout.
- Tapping a day opens a `DraggableScrollableSheet` (`_WorkoutDetailSheet`) showing every workout logged that day: duration, exercise count, total sets, total volume (`Σ reps×weight`), and a full per-exercise/per-set breakdown, all using the currently-saved weight unit. Tapping a day with zero workouts still opens the sheet with an empty-state message.
- Legend row explains the workout-day dot vs. rest-day (visual only — the calendar does not currently mark rest days distinctly on the grid itself, despite the legend implying it does; see §7).

### 4.6 Settings (weight unit only)
- No dedicated settings screen exists. The only user-facing setting — weight unit (kg/lbs) — is toggled inline from `ActiveScreen` via the pill button described in §4.3. It's read elsewhere (Home/History/Calendar) purely for display formatting.

### 4.7 Background / async work
- No true background tasks, isolates, or platform channels. All "timers" (`WorkoutTimerBloc`, `RestTimerBloc`) are `Stream.periodic(Duration(seconds: 1))` subscriptions living inside the BLoC for as long as the BLoC instance is alive (i.e., only while the user stays on that route — there is no background/notification-based timer that survives app backgrounding or navigation away).

---

## 5. Data Models & Schemas

### 5.1 Domain Entities (`domain/entities/`)

```dart
class ExerciseSet {
  final int reps;
  final double weight;
}

class Exercise {
  final String name;
  final List<ExerciseSet> sets;
}

class Workout {
  final String id;              // UUID v4 string
  final DateTime date;          // set to DateTime.now() at WorkoutFinished time
  final int durationSeconds;
  final List<Exercise> exercises;
}
```
None of these implement `Equatable` or `copyWith` — they are plain immutable value holders, always fully reconstructed rather than patched.

### 5.2 Data Models (`data/models/`)
`WorkoutModel extends Workout`, `ExerciseModel extends Exercise`, `ExerciseSetModel extends ExerciseSet` — each adds a covariant typed list (`exerciseModels` / `modelSets`) plus `fromJson`/`toJson`/`fromEntity` factories. **The JSON codec is currently dead code** — nothing in the app serializes to/reads from JSON; persistence goes through raw `sqflite` column maps instead (see §7).

### 5.3 SQLite Schema (`data/datasources/workout_database.dart`)

Database file: `gympulse.db`, **version 2**. `PRAGMA foreign_keys = ON` is set in `onConfigure` (the only hook where it takes effect — it is a no-op inside the create/upgrade transaction). `onUpgrade` is an `if (oldVersion < N)` ladder; `onDowngrade` deletes.

```sql
CREATE TABLE workouts (
  id TEXT PRIMARY KEY,
  date TEXT NOT NULL,                 -- ISO8601 local, = session START time
  duration_seconds INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'done' -- 'done' | 'draft'  (v2)
);

CREATE TABLE exercises (
  id TEXT PRIMARY KEY,                -- UUID v4, generated per-exercise at save time (not the domain id)
  workout_id TEXT NOT NULL,
  name TEXT NOT NULL,
  position INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (workout_id) REFERENCES workouts(id) ON DELETE CASCADE
);

CREATE TABLE sets (
  id TEXT PRIMARY KEY,                -- UUID v4, generated per-set at save time
  exercise_id TEXT NOT NULL,
  reps INTEGER NOT NULL,
  weight REAL NOT NULL,               -- kilograms, always
  position INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
);
```
`position` columns preserve insertion order on read. Cascades fire on `deleteWorkout` and on every `upsertWorkout` (`INSERT OR REPLACE` on the parent row deletes children via FK, then they are reinserted). A draft is an ordinary row with `status='draft'`; `getWorkouts` filters `status='done'`.

### 5.4 SharedPreferences Keys (no schema, just documented keys)

| Key | Type | Written by | Meaning |
|---|---|---|---|
| `onboarding_complete` | bool | `OnboardingScreen` | Gates the router redirect |
| `user_name` | String | `OnboardingScreen` | Displayed in Home greeting |
| `weight_unit` | String (`'kg'`\|`'lbs'`) | `SettingsRepositoryImpl` | Display unit everywhere |
| `streak_count` | int | `StreakLocalDatasourceImpl` | Current consecutive-day streak |
| `last_workout_date` | String (ISO date, day-truncated) | `StreakLocalDatasourceImpl` | Last day a **workout** was logged (never written by a rest day) |
| `last_streak_day` | String (ISO date) | `StreakLocalDatasourceImpl` | Last day the streak was kept (workout **or** rest). Falls back to `last_workout_date` for pre-split installs |
| `rest_days_remaining` | int | `StreakLocalDatasourceImpl` | Remaining tokens in the current ISO week |
| `week_start_date` | String (ISO date) | `StreakLocalDatasourceImpl` | Monday of the current ISO week |
| `last_rest_day_date` | String (ISO date) | `StreakLocalDatasourceImpl` | Prevents marking more than one rest day per calendar day |

---

## 6. Key Implementation Details

### 6.1 Dependency Injection (`injection_container.dart`)
Single `init()` function, awaited before `runApp`. Registration order matters (each depends on the previous):
1. `SharedPreferences` instance → singleton.
2. `WorkoutLocalDatasource` → **lazy** singleton (sqflite-backed impl).
3. `StreakLocalDatasource` → singleton (constructed eagerly, needs prefs).
4. Three repositories → singletons, each taking its datasource.
5. Six use cases → singletons, each taking its repository.
6. Five BLoCs → **factories** (fresh instance every `sl<XBloc>()` call), each taking its use case(s).

### 6.2 Routing & Guards (`presentation/router.dart`)
- `createRouter(bool onboardingComplete)` takes the already-read onboarding flag to pick `initialLocation` (avoids a flash of the wrong screen).
- `redirect` callback re-checks the same flag on every navigation (defense in depth beyond just `initialLocation`).
- Routes `/`, `/active`, `/history` construct their BLoCs inline in the route `builder`, wired as `MultiBlocProvider`s scoped to that screen only.
- `/history` is given `key: UniqueKey()` specifically so revisiting it always creates a new `HistoryScreen` state (forces the one-shot `FutureBuilder` fetch to re-run).
- Custom `errorBuilder` renders a themed 404 page with a "Go Home" button rather than the default Flutter error screen.

### 6.3 Streak & Rest-Day Algorithm (`StreakLocalDatasourceImpl`)
Semantics are documented on the class. Summary: a streak is consecutive civil days each of which is a workout or a marked rest day; it increments once per *training* day; rest days bridge without incrementing; a lapse > 1 day reads as 0. Rest allowance is `kRestDaysPerWeek` per ISO Monday week. All day math goes through `domain/streak_rules.dart` (`civilDaysBetween` projects onto UTC — DST-safe). `markRestDay` refuses when there is no live streak, when a workout was already logged today, or when a rest was already marked today; it writes its same-day guard *before* decrementing. `StreakBloc` runs `StreakUpdated`/`RestDayMarked` under `sequential()`. The clock is injected (`clock:`), which is how the 21-case test suite exists.

### 6.4 Timer BLoCs
Both `WorkoutTimerBloc` and `RestTimerBloc` use `Stream.periodic(Duration(seconds: 1))` piped back into `add()` (self-feeding event loop) rather than a raw `Timer.periodic` mutating state directly — keeps all state transitions inside BLoC's `on<Event>` handlers. Both cancel their `StreamSubscription` on `close()` to avoid leaking ticks into a disposed BLoC. `RestTimerBloc` additionally tracks `totalDuration` separately from the ticking `seconds` remaining, so a paused-then-resumed timer's circular progress ring keeps the original denominator instead of resetting to the resumed remaining time.

### 6.5 No network layer
There are no API endpoints, no `http`/`dio` dependency, and no external integrations of any kind. All "integrations" are local platform packages (`sqflite`, `shared_preferences`).

### 6.6 Theming
All theme data is defined inline as one large `ThemeData` literal in `main.dart` (not extracted into a separate theme file/class). Custom warm brown/cream Material 3 `ColorScheme` (hex-coded, not derived from a seed color), `Playfair Display` for display/headline/title text styles and `DM Sans` for body/label styles (via `google_fonts`, **bundled** under `assets/fonts/` with runtime fetching disabled). Component themes are set for `Card`, `ElevatedButton`, `AppBar`, and `InputDecoration`.

---

## 7. Current Project State

### 7.1 Working and tested
- Everything in §4, plus draft persistence/resume, edit and delete. 39 unit/bloc tests + 1 on-device integration test; `flutter analyze` clean.
- Save failures are recoverable (remove the offending set/exercise, retry). Load failures render `LoadErrorView`, never the empty state. Bloc errors are logged via `AppBlocObserver`.

### 7.2 Known gaps / next steps
- **BUG-09 partially addressed**: Home's "Longest run" tile counts workout-day runs and cannot see rest days; the streak card can. Reconciliation needs rest days as queryable rows.
- History, Home and Calendar each call `GetWorkouts` directly via `FutureBuilder`; History calls `DeleteWorkout` directly. A shared `HistoryBloc` is the next refactor.
- `getWorkouts` is N+1 by design; revisit past ~2000 workouts.
- No `CHECK` constraints on `sets` (needs a table rebuild → v3).
- Rest-timer sheet keeps its two documented `!_debugDoingThisLayout` workarounds; re-verify if you change how it opens/closes.

## 8. Corrections to the original version of this document
- Claimed the redirect guard might capture a stale onboarding flag — it reads live from prefs on every navigation. Not a bug.
- Claimed `PRAGMA foreign_keys` was only in `onCreate` — it was in two places; the `onCreate` copy was a silent no-op (inside a transaction), the post-open copy worked by accident. Now in `onConfigure`.
- Claimed `didChangeDependencies` refired on keyboard/MediaQuery changes — Home only subscribed to `Theme`. The real defect was a duplicate `StreakLoaded` dispatch (router + screen).
- Said `ConflictAlgorithm.replace` would orphan/duplicate children on re-save — with FKs ON it cascades cleanly; that path is now used deliberately for drafts and edits.
- Listed the streak edge cases as handled — DST spring-forward broke it (23h between local midnights → `inDays == 0`), and `last_workout_date` was overloaded to mean two things.
- Listed Web/Windows/Linux as supported — sqflite had no implementation there.
- Did not mention that `WorkoutErrorState` made any save failure permanent (BUG-26) or that the `database` getter could open the DB twice (BUG-12).
