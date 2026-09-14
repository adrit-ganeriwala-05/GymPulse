# GymPulse — Project Context

> Sole onboarding document for AI instances. Read this before touching code. It reflects the codebase as of commit `7518cbc` (local) / `fcbda46` (origin/main — local is 3 README-only commits behind; run `git pull` before starting work). No other code changes are pending upstream.

---

## 1. Project Overview

**GymPulse** is a single-user, offline-first mobile/desktop/web Flutter app for tracking gym workouts. It has no backend, no auth, no network calls — everything persists locally on-device via SQLite (`sqflite`) and `shared_preferences`.

Primary use case: a solo gym-goer opens the app, starts a workout session, adds exercises, logs sets (reps × weight) as they go, times their rest between sets, finishes the workout (which is saved to local SQLite), and tracks a daily workout **streak** with a limited weekly rest-day allowance. Secondary flows: browsing workout history, viewing a monthly calendar of workout days, and toggling the displayed weight unit (kg/lbs).

There is no multi-user support, no cloud sync, no export, and no editing/deleting of past workouts.

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
| `flutter_animate` | ^4.5.0 | 4.5.2 | **Declared but currently unused** — no `.animate()` calls anywhere in `lib/` |
| `google_fonts` | ^6.1.0 | 6.3.3 | Playfair Display + DM Sans typography |
| `sqflite` | ^2.3.2 | 2.4.2+1 | Local SQLite database for workout history |
| `path` | ^1.9.0 | 1.9.1 | Joins DB file path (`sqflite` helper) |

**Dev dependencies**
- `flutter_test` (SDK)
- `flutter_lints` ^6.0.0 (resolved 6.0.0) — `analysis_options.yaml` just includes `package:flutter_lints/flutter.yaml` with no rule overrides. `flutter analyze` currently reports **zero issues**.

**Platforms configured**: Android, iOS, macOS, Web, Windows, Linux (all platform folders present and scaffolded by `flutter create`; no platform-specific native code has been added beyond defaults).

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
│   │   ├── entities/
│   │   │   ├── exercise.dart              # Exercise, ExerciseSet (plain, non-Equatable)
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
│   │       ├── save_workout.dart
│   │       └── update_streak.dart
│   ├── data/
│   │   ├── datasources/
│   │   │   ├── workout_database.dart       # sqflite singleton, schema DDL
│   │   │   ├── workout_local_datasource.dart   # CRUD against sqflite
│   │   │   └── streak_local_datasource.dart    # streak/rest-day logic, SharedPreferences-backed
│   │   ├── models/
│   │   │   ├── exercise_model.dart         # ExerciseModel/ExerciseSetModel extend domain entities
│   │   │   └── workout_model.dart          # WorkoutModel extends Workout; unused JSON codec (see §7)
│   │   └── repositories/                   # implement domain interfaces, delegate to datasources
│   │       ├── settings_repository_impl.dart
│   │       ├── streak_repository_impl.dart
│   │       └── workout_repository_impl.dart
│   └── presentation/
│       ├── router.dart                     # GoRouter config, per-route BlocProviders, auth-style redirect guard
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
│           ├── exercise_log_card.dart      # used on ActiveScreen
│           ├── workout_summary_card.dart   # used on HomeScreen + HistoryScreen
│           ├── exercise_card.dart          # ⚠ dead code — no imports anywhere
│           ├── streak_badge.dart           # ⚠ dead code — no imports anywhere, off-brand dark palette
│           └── streak_card.dart            # ⚠ dead code — no imports anywhere
│           └── timer_display.dart          # ⚠ dead code — no imports anywhere
├── test/
│   └── widget_test.dart                    # placeholder only, asserts `true`
├── pubspec.yaml / pubspec.lock
├── analysis_options.yaml                   # default flutter_lints, no custom rules
└── android/ ios/ macos/ web/ windows/ linux/   # standard flutter create scaffolds, unmodified
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

Database file: `gympulse.db` (via `getDatabasesPath()`), version `1`, no migrations defined yet.

```sql
PRAGMA foreign_keys = ON;

CREATE TABLE workouts (
  id TEXT PRIMARY KEY,
  date TEXT NOT NULL,                 -- ISO8601 string
  duration_seconds INTEGER NOT NULL DEFAULT 0
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
  weight REAL NOT NULL,
  position INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
);
```
`position` columns preserve insertion order on read (`ORDER BY position ASC`) since SQLite doesn't guarantee row order otherwise. Cascading deletes are configured but **nothing in the app ever deletes a workout**, so the cascade is currently unexercised.

### 5.4 SharedPreferences Keys (no schema, just documented keys)

| Key | Type | Written by | Meaning |
|---|---|---|---|
| `onboarding_complete` | bool | `OnboardingScreen` | Gates the router redirect |
| `user_name` | String | `OnboardingScreen` | Displayed in Home greeting |
| `weight_unit` | String (`'kg'`\|`'lbs'`) | `SettingsRepositoryImpl` | Display unit everywhere |
| `streak_count` | int | `StreakLocalDatasourceImpl` | Current consecutive-day streak |
| `last_workout_date` | String (ISO date, day-truncated) | `StreakLocalDatasourceImpl` | Last day counted toward the streak (workout **or** rest day) |
| `rest_days_remaining` | int | `StreakLocalDatasourceImpl` | Remaining rest-day tokens in the current 7-day window |
| `week_start_date` | String (ISO date) | `StreakLocalDatasourceImpl` | Anchor for the rolling 7-day rest-day allowance |
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
This is the most subtle business logic in the app, entirely in `data/datasources/streak_local_datasource.dart`:
- **`updateStreak()`** (called after every finished workout): compares `today` to `last_workout_date`. Same day → no-op (multiple workouts/day don't double-count). Exactly 1 day gap → increment streak. Any gap `>1` day → reset streak to `1`. No prior date → initialize streak to `1`. Always calls `_initWeekIfNeeded()` afterward.
- **`_initWeekIfNeeded()`**: if no `week_start_date` is stored, or the current week has run ≥7 days since its start, (re)anchors `week_start_date = today` and resets `rest_days_remaining = 2`. This is a **rolling 7-day window anchored to whenever the user first opens the app in a new cycle**, not a calendar week (not Mon-Sun) — it only advances when `getRestDaysRemaining()` or `updateStreak()` is called, i.e. lazily on next use, not via a background job.
- **`markRestDay()`**: guards against (a) marking a day outside the currently tracked 7-day window (defensive check against a stale window), and (b) marking the same calendar day twice (`last_rest_day_date` check). If `rest_days_remaining > 0`, decrements it, records `last_rest_day_date`, **and also bumps `last_workout_date` to today** — meaning a rest day counts as a "covered" day for streak-continuity purposes (prevents the streak from breaking) without incrementing the streak counter itself.
- Two rest days are allotted per rolling week; there is no UI to configure this limit — it's a hardcoded `2` default in three places (`getRestDaysRemaining` fallback, `_initWeekIfNeeded`).

### 6.4 Timer BLoCs
Both `WorkoutTimerBloc` and `RestTimerBloc` use `Stream.periodic(Duration(seconds: 1))` piped back into `add()` (self-feeding event loop) rather than a raw `Timer.periodic` mutating state directly — keeps all state transitions inside BLoC's `on<Event>` handlers. Both cancel their `StreamSubscription` on `close()` to avoid leaking ticks into a disposed BLoC. `RestTimerBloc` additionally tracks `totalDuration` separately from the ticking `seconds` remaining, so a paused-then-resumed timer's circular progress ring keeps the original denominator instead of resetting to the resumed remaining time.

### 6.5 No network layer
There are no API endpoints, no `http`/`dio` dependency, and no external integrations of any kind. All "integrations" are local platform packages (`sqflite`, `shared_preferences`).

### 6.6 Theming
All theme data is defined inline as one large `ThemeData` literal in `main.dart` (not extracted into a separate theme file/class). Custom warm brown/cream Material 3 `ColorScheme` (hex-coded, not derived from a seed color), `Playfair Display` for display/headline/title text styles and `DM Sans` for body/label styles (both via `google_fonts`, fetched at runtime — first launch requires the font to download unless cached, per `google_fonts` package behavior). Component themes are set for `Card`, `ElevatedButton`, `AppBar`, and `InputDecoration`.

---

## 7. Current Project State

### 7.1 Fully functional / production-ready
- Onboarding flow with persisted completion flag and router-level enforcement.
- DI graph, app boot sequence, theming.
- Full active-workout flow: start timer, add exercises (with dedupe), log sets, auto-prompted rest timer with two documented layout-bug workarounds, finish-with-confirmation, error handling on save failure (`WorkoutErrorState` + `SnackBar`, doesn't crash).
- SQLite persistence of finished workouts (transactional, FK-cascading schema) and retrieval, newest-first.
- Streak + rolling weekly rest-day tracking (`SharedPreferences`-backed), including edge cases for same-day double-workouts, day gaps, and week-boundary rollover.
- Weight unit toggle, persisted and reflected consistently across Home/Active/History/Calendar.
- History list, Calendar month view with per-day workout detail sheet.
- `flutter analyze` is clean (zero issues) against `flutter_lints` defaults.
- Git repo is real (`github.com/adrit-ganeriwala-05/GymPulse`), 4 commits total; local checkout is 3 commits behind `origin/main` (all three are README wording/typo fixes only, no code drift) — safe to `git pull` before further work.

### 7.2 Partially implemented / dead code / inconsistencies
- **Four orphaned widgets, never imported anywhere**: `exercise_card.dart`, `streak_badge.dart`, `streak_card.dart`, `timer_display.dart`. `StreakBadge`/`StreakCard` even use a different, older dark navy/red color palette (`0xFF16213E`/`0xFFE94560`) inconsistent with the current warm brown/cream theme — clear leftovers from an earlier design iteration, superseded by the inline streak card built directly into `HomeScreen`. Safe to delete, or worth asking the user before wiring back in.
- **Dead JSON (de)serialization**: `WorkoutModel`/`ExerciseModel`/`ExerciseSetModel`'s `fromJson`/`toJson` are never called anywhere; the real sqflite datasource builds/reads raw `Map<String, Object?>` column maps directly. Likely a remnant of an earlier `shared_preferences`+JSON persistence design that was replaced by sqflite without removing the old codec.
- **Duplicate/competing "streak" concepts**: `HomeScreen`'s "Best Streak" stat tile is computed client-side from the raw workout list (longest run of consecutive calendar days with ≥1 workout) and is **independent of** `StreakBloc.currentStreak` (which is persisted, increments on rest days too via `last_workout_date`, and is what the streak card actually displays). A future change to one will not automatically stay consistent with the other — worth unifying or clearly renaming to avoid confusion (e.g. "Best Streak" vs. "Current Streak" don't currently share a definition of "streak").
- **`WorkoutBloc.HistoryRequested`/`WorkoutHistoryState` are unused** — no screen ever dispatches `HistoryRequested()`. `HistoryScreen`, `HomeScreen`, and `CalendarScreen` all bypass the BLoC and call `sl<GetWorkouts>()` directly. This is a dead code path inside an otherwise-used BLoC, and a real duplication of "how do I fetch workouts" across three screens.
- **Calendar legend implies rest days are marked on the grid**, but `_CalendarView`'s `markerBuilder` only checks `workoutsByDay` — there is no rest-day marker rendered anywhere on the calendar despite the legend showing a "Rest day" dot.
- **No workout editing or deletion** exists anywhere in the UI or data layer (no `deleteWorkout`/`updateWorkout` methods on `WorkoutRepository` at all). The `ON DELETE CASCADE` FKs are defined but unexercised. If this is added later, note the `saveWorkout` insert uses `ConflictAlgorithm.replace` keyed on the *workout* row's `id` only — replacing a workout row would **not** clear its old child `exercises`/`sets` rows first, so naively reusing `saveWorkout` for "edit" would leave orphaned/duplicate child rows. A real edit feature needs an explicit delete-children-then-reinsert (or a dedicated update path).
- **`getWorkouts()` has an N+1 query pattern**: one query for all workouts, then one query per workout for its exercises, then one query per exercise for its sets. Fine at hobbyist data volumes; will need batching/joins if workout history grows large.
- **`flutter_animate` is an unused dependency** — declared in `pubspec.yaml`, never imported. Either remove it or it's earmarked for animation work not yet started.
- **No real test coverage**: `test/widget_test.dart` is the unmodified `flutter create` placeholder (`expect(true, isTrue)`). No unit tests exist for the streak algorithm (the most bug-prone logic in the app), no BLoC tests, no widget tests for any of the five screens.
- **Silent failure fallback pattern**: `HomeScreen`, `HistoryScreen`, and `CalendarScreen` all do `snapshot.data ?? []` in their `FutureBuilder`s — a `GetWorkouts()` failure (e.g., a corrupted DB file) renders identically to "no workouts yet" with no error surfaced to the user, and no logging.
- **Timers do not survive navigation or backgrounding**: both `WorkoutTimerBloc` and `RestTimerBloc` live only as long as their screen's BLoC instance; backgrounding the app or navigating away and back resets them (there is no persisted "workout in progress" draft state — closing `/active` and reopening it always starts a fresh, empty `WorkoutBloc`).

### 7.3 Known bugs / risk areas to watch
- The two documented `!_debugDoingThisLayout` workarounds in `active_screen.dart` (`_showRestTimerSheet`'s post-frame-callback deferral, and the rest-timer-finished `Navigator.pop()` deferral) indicate this is a real, previously-hit Flutter timing bug in this exact flow — if you refactor how/when the rest-timer sheet opens or closes, re-verify these races don't reappear (test specifically: logging a set immediately after the keyboard was focused, and letting the rest timer run out naturally while the sheet is open).
- `_initWeekIfNeeded()`'s "rolling week" only advances lazily, the next time `getRestDaysRemaining()` or `updateStreak()` runs — if a user doesn't open the app for several weeks, the very next open will correctly reset to a fresh 2-rest-day window anchored to "today" (verified by the `>=7` check), but there's no historical record of skipped weeks; this is expected/acceptable for a purely local rest-day allowance, just don't assume `week_start_date` reflects continuous usage.
- `HomeScreen._formatDate`/`_CalendarViewState._formatDetailDate`/`WorkoutSummaryCard._formatDate` each hand-roll their own day/month name arrays and `weekday`/`month` index math independently (three near-duplicate implementations) — a good target for extraction into a shared date-formatting utility if you touch any of them.

### 7.4 Obvious next steps (not started)
- Decide fate of the four dead widgets and the dead JSON codec (delete or integrate).
- Add a real settings screen if more preferences are ever needed (currently weight-unit-only, buried in `ActiveScreen`).
- Add workout edit/delete.
- Add rest-day markers to the calendar grid to match the legend, or remove the misleading legend entry.
- Add unit tests around `StreakLocalDatasourceImpl` given its date-math complexity.
- Reconcile the "Best Streak" vs. "Current Streak" definitions on `HomeScreen`.
