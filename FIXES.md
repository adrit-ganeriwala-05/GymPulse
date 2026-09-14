# FIXES — what changed, what was cut, what to overrule

Base: `fcbda46` (origin/main after pull). Every commit below references its BUG-IDs; explanations live in the commit bodies and in `WALKTHROUGH.md`.

## Corrections applied to the report before starting
- **BUG-02 → Medium.** Kept the fix (validation at entry with `errorText`), relabelled.
- **BUG-26 (Critical, new).** `WorkoutErrorState` carried the failed exercise list with no way to edit it, so *any* save failure was permanent. Fixed in Stage 1: `SetRemoved`/`ExerciseRemoved` + delete affordances, and the bloc returns to `InProgress` after an error so the mutation handlers accept the fix.
- **GetWorkouts N+1 — verdict: not a bug at this volume.** 1 + N + N·M cheap local reads; at a solo user's ~200 workouts × 5 exercises that is ~1,200 queries per load, sub-100 ms on device. Becomes a bug past roughly **2,000 workouts** (≈12k queries, visible spinner). Comment left in `_hydrate`; revisit with a JOIN then.
- **BUG-17 incomplete** — the back-gesture half is fixed with `PopScope`; the backgrounding/process-death half is closed by Feature A's write-through draft (see Stage 6).
- `project_context.md` committed at the root and updated (§8 = corrections).

## Stage 1 — stop data loss (`fa51372`, `943a3c8`)
BUG-26, BUG-02, BUG-23 · BUG-12, BUG-05. Two commits, not four: the card/bloc changes share one widget; the two DB fixes share one file.

## Stage 2 — schema changeable (`b7a325c`)
BUG-04: `onUpgrade` ladder, `onDatabaseDowngradeDelete`. Version stayed 1 here; Stage 6 bumped it to 2.

## Stage 3 — streak cluster (`aeff763`, `9b59f4c`, `6c385f7`)
Refactor (clock injection, no behaviour change) · BUG-03, 07, 10, 18, 19, 22 (+ BUG-09 rename landed here — same edit) · BUG-08.
**Behaviour changes:** a lapsed streak now reads 0 instead of the stale count; rest days reset on Monday (one transitional short/long week for existing users); "This week" is the calendar week, not the last 168 h; Mark Rest Day is hidden until a streak exists and on days already trained. Unilateral: `getStreak()` returning 0 for a lapsed streak — overrule if you want the stale count shown.
21 datasource tests, injected clock. Pre-split installs fall back from `last_workout_date` when `last_streak_day` is absent — tested.

## Stage 4 — what's shown (`9a584ee`, `5522c64`)
BUG-06 · BUG-11 + BUG-14 · BUG-01 · BUG-09 rename.
**Units:** storage is kg; conversion at parse and render only (`presentation/units.dart`). Existing rows treated as kg per decision 1 — no data migration, column comment documents it. `formatWeight` renders 1 decimal (0 for volumes); `100.0 kg` now reads `100 kg`.
**Errors:** `LoadErrorView` with retry at all three sites; Home gained its missing `waiting` branch; `AppBlocObserver` + `FlutterError.onError` (chained, not replaced) are the first log sinks. `_onFinished` forwards to `addError`.

## Stage 5 — Mediums/Lows (`9c3dc33`, `c7d8f82`)
BUG-13, 15, 16, 17 (gesture half), 20, 24, 25.
Deleted per decision 5: four orphaned widgets, `flutter_animate`, the JSON codec, `HistoryRequested`/`WorkoutHistoryState` (not wired — `push()` already creates a fresh History state, so dropping `UniqueKey` was the whole fix). `web/`, `windows/`, `linux/` removed; README narrowed. `sqflite_common_ffi` (dev) runs the real datasource against real SQLite.
Formatters consolidated into `presentation/format.dart`; **90-minute workouts now render `1:30:00`** (were `90:00`). Phantom "Rest day" legend removed.

**BUG-21 — fixed in round 2.** Playfair Display and DM Sans variable TTFs (OFL, from google/fonts) bundled under `assets/fonts/` with the `Family-Variant.ttf` names `google_fonts` resolves from the asset manifest; `allowRuntimeFetching = false` so a missing face fails loudly instead of silently after a network attempt. +1.6 MB. No Dart call sites changed.

## Stage 6 — features (`4ceac8c`, `9ff7dfa`)
Picked A (persisted draft) and B (edit/delete) — reasoning in `FEATURE_PROPOSALS.md`.
**A:** schema v2 (`status` column, first real `onUpgrade` step); draft = ordinary workout row; write-through on every mutation under `sequential()`; resume on `WorkoutStarted`; stopwatch seeded from `now − startedAt`; Home banner with Resume/Discard. **No `AppLifecycleState` hook** — `paused` does not fire on a kill; write-through is the only strategy that survives all three cases. Overrule if you wanted the lifecycle-hook exercise specifically.
**B:** long-press in History → Edit (reopens `/active` in edit mode via route `extra`; Save calls `UpdateWorkout`, keeps date, no streak) or Delete (confirm; first real `ON DELETE CASCADE`).
Behaviour change: leaving `/active` mid-session no longer prompts — the draft is already saved; only an unsaved *edit* asks.
Tests: 5 datasource cases incl. **v1 → v2 migration on a hand-built v1 file**, 8 bloc cases with in-memory fakes (write-through, resume, finish, failure recovery, edit semantics).

## Judgment calls you may want to overrule
1. `getStreak()` → 0 when lapsed (Stage 3).
2. Leaving `/active` with a draft is silent (Stage 6) — a snackbar "Saved as draft" would be a one-liner.
3. History calls `DeleteWorkout` directly rather than via a bloc, matching its existing `GetWorkouts` read path. `HistoryBloc` is the named next refactor.
4. `UpdateWorkout`/`DiscardDraft` exist as separate use cases despite sharing SQL with `SaveWorkout`/`DeleteWorkout` — policy boundary, argued in `WALKTHROUGH.md` §5.
5. Weight display rounds to 1 decimal.

## Found along the way (not in the report)
- `main()` replaced `FlutterError.onError`, which breaks any test binding; now chains. Caught by the integration test.
- Home optimistically rendered "2 rest days left" before load; now shows nothing until loaded.

## Verification (executed, not asserted)
- `flutter analyze` → `No issues found! (ran in 1.3s)`
- `flutter test` → `+39: All tests passed!` (21 streak · 9 datasource on real SQLite via ffi, incl. v1→v2 migration · 8 WorkoutBloc · 1 placeholder)
- `flutter test integration_test/app_flow_test.dart -d "iPhone 17 Pro"` (iOS 26.3 simulator) → `00:31 +1: All tests passed!`
  Walked, from a **hand-seeded v1 database** so `_onUpgrade` ran on the real plugin: onboarding (empty name rejected; swipe disabled) → Home shows the migrated legacy workout, streak 0, no rest button → Begin → Add "Bench" → `0` reps rejected with visible `Must be > 0` → log 10×100 → rest sheet opens → close → **remove set** → log 8×60 → rest sheet → close → Finish → Save & Finish → Home: streak card, "Longest run", Mark Rest Day hidden (trained today, BUG-07) → Calendar (no phantom "Rest day" legend) → back → View all → History shows legacy (Jan 5) + new → long-press legacy → Delete → confirm → gone (**cascade on device**) → long-press new → Edit → "Edit Workout" screen with "Bench".
- Not walked on device: Mark Rest Day (by design unreachable on a workout day; covered by 7 unit cases), draft resume across process kill (covered by bloc + datasource tests; the draft banner renders from the same `GetDraft` path).

## Found by the device run (all fixed, `lib/` + integration test in one commit)
1. **Onboarding pages 2/3 overflowed 49 px** while the keyboard from page 1 was still up — bare `Column`, no scroll. Yellow stripes mid page-slide: almost certainly the "animation bug" you mentioned. Now `SingleChildScrollView` + unfocus before `nextPage`.
2. **Finish FAB covered the ✓ button** with the keyboard open (full-width `centerFloat` FAB floats up onto the entry row). Hidden while `viewInsets.bottom > 0`.
3. **Rest-sheet Start button threw `BoxConstraints forces an infinite width`** — theme `minimumSize(double.infinity, 56)` inside a centered `Row`. In debug the sheet body never painted; this is the real cause behind the code's old "only the dark scrim painted" comment, which blamed a keyboard race. Bounded to 140×48.
4. **Tapping a Home card never navigated to History** — the card's inner `InkWell` wins the gesture arena over the outer `GestureDetector`. Replaced with an explicit "View all" link.
5. `_reload() => setState(() => _x = …)` returned the Future from the callback; framework assert. Block body in all three screens.
6. `main()` replaced `FlutterError.onError`; now chains.

## Round 2 (review follow-ups)
1. **Draft leaking into reads — not a bug.** Audited every read path: there is exactly one, `getWorkouts()` with `status = 'done'`; Home tiles, Longest run, recent activity, Calendar grouping and History all derive from it. The aggregations lived in widget `build`s, so they were untestable; extracted to `domain/workout_stats.dart` (`countThisWeek`, `countThisMonth`, `longestRun`, `groupByDay`, `mostRecentDay`) and asserted end-to-end from the ffi datasource with a zero-exercise draft seeded today: invisible to all five.
2. **Stopwatch — fixed.** Elapsed is now persisted, not derived: `WorkoutInProgressState.elapsedSeconds`, `WorkoutElapsedUpdated` checkpointed from the timer every 10 s and on pause/stop (single-column `UPDATE` via `RecordDraftElapsed`, not a full replace), carried on every mutation snapshot, and seeded back into the timer on resume. A kill loses ≤10 s of *active* time; a three-day-old draft resumes at its real elapsed. Paused-at-death resumes running (the pause flag is not persisted) — noted, small.
   **Stale-draft policy: keep, show age, prominent Discard; no auto-discard.** A gym app that deletes logged sets on its own violates the point of Feature A; the cost of a stale resume is one workout dated from its real start, which is arguably correct, and the banner shows "started N days ago · M active" beside an `OutlinedButton` Discard so the choice is informed. A cap would trade a rare mis-dated workout for silent data loss.
3. **getStreak — both confirmed, now asserted.** Gap of exactly 1 reads alive (`_isAlive` is `<= 1`; test: train Mon+Tue, read Wed morning → 2). `getStreak()` never writes (test snapshots every pref before a lapsed read and asserts equality; `streak_count` still holds the old value — `updateStreak` owns the write).
4. **Home card tap — fixed properly.** `WorkoutSummaryCard` takes an optional `onTap` threaded into its own `InkWell`; Home passes the navigation. Outer `GestureDetector` removed. "View all" kept. Integration test now taps the card.
5. **"Saved as draft" snackbar** on leaving `/active` with logged exercises. Taken.
6. **Edit-mode rounding — not a bug.** Nothing prefills the weight field; edit mode carries stored `ExerciseSet` doubles through untouched, and only new sets pass through `displayToKg` once. Test: edit `61.2349 kg` twice → stored value bit-identical.
7. **BUG-21 — fixed** (above).
New tests: +2 streak, +2 datasource, +3 bloc → **46 unit/bloc**. One integration run.

## Round 3 (pause flag · Android · coverage)
**1 · Pause flag — fixed.** Schema v3 `timer_paused`; `WorkoutDraft` carries it; every checkpoint and mutation snapshot writes it; `WorkoutTimerStarted(paused:)` seeds `WorkoutTimerPausedState` directly. Stopped is persisted as paused. Snapshot audit: rest-timer countdown (dropped, seconds-scale), unsubmitted input/open forms (UI-only), weight unit (own pref) — nothing else resumes differently. Found while walking Android: **edit mode ran the clock** from the saved duration — same class; now seeds paused.
**2 · Android — what broke that iOS didn't.**
- **System back on `/active` exited the app.** go_router 13 `popRoute` never calls `maybePop` at a root route (`delegate.dart:59`), so `PopScope` was bypassed. `/active` is now nested under `/`; Home refreshes via `RouteObserver.didPopNext`. No `lib/` platform conditional — a routing-structure fix that applies everywhere.
- **Status-bar icons** light-on-cream: `AppBarTheme.systemOverlayStyle = dark`. The one Android-only line.
- **Harness limit:** `flutter test integration_test/…` reinstalls the APK on Android every run (observed `Installing …` on run 2 of the same file; prefs marker gone), wiping data. Process death was therefore verified against a real debug build via `adb`: `am force-stop` mid-session → relaunch → banner `1 exercises · 00:55 active` → Resume → **paused at 00:55**, 5 s later still 00:55, set intact. `draft_death_test.dart` is kept as the in-process seed/resume script but cannot prove persistence under this harness — documented in the file.
- Passed unchanged on Android 17: full flow from a hand-seeded v1 DB (v1→v3 ladder on `sqflite_android`), keyboard insets on the log-set row and rest sheet, every bundled font weight, predictive/system back out of edit → confirm dialog.
- **Final runs (one each):** Android emulator (Pixel 9 Pro XL, Android 17) → `00:30 +1: All tests passed!` · iOS simulator (iPhone 17 Pro, iOS 26.3) → `00:31 +1: All tests passed!`. `flutter analyze` → `No issues found!` · `flutter test` → `+90: All tests passed!`
- **Nothing remains broken that I know of.**
**3 · Coverage — 90 tests** (was 39): datasources 35 (streak 23 · workout/SQLite 12) · repositories 3 · domain stats 8 · blocs 23 (Workout 12 · WorkoutTimer 7 · RestTimer 4) · screens 15 (Active 7 · Home 4 · History 2 · Onboarding 2) · widgets 2 · units/settings 3 · placeholder 1. Each names its bug (see commit `134397d`).
**Still untested, and why:** `CalendarScreen` (table_calendar rendering; the only logic — `groupByDay` — is covered in domain); `StreakBloc` itself (three passthrough handlers; the datasource beneath has 23 cases); `LoadErrorView` in isolation (covered via History); go_router redirect (would need a router harness; covered by both device runs); the rest-timer sheet's auto-close on finish (timing-dependent; the bloc's finish transition is unit-tested).

## Spend
Approximate, from token volume: Stage 1 $7 · Stage 2 $9 · Stage 3 $16 · Stage 4 $24 · Stage 5 $33 · Stage 6 $52 · Stage 7 (8 simulator runs) + docs ≈ $70. Round 2 ≈ $12 → ≈ $82. Round 3 (2 emulator + 2 simulator runs, ~20 screenshots) ≈ $30 → **≈ $112 total, token-volume estimate; no console access from this session**.
