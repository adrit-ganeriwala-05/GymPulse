# GymPulse — Audit 2 (round 4, independent review of `fcbda46..68a61d6`)

**Date:** 2026-09-14
**Scope:** everything added since `fcbda46` — draft lifecycle, edit/delete, migration ladder, `workout_stats`, `units`, routing restructure, the 90-test suite. Pre-existing code only where the new code implicates it.
**Method:** docs read as claims; every finding below was reproduced by a failing test before being called a bug. Items I could not reproduce are filed as suspicions and say so.
**Baseline:** `flutter analyze` clean · `flutter test` `+90` · both device suites green (round 3).

---

## 0. Summary

| ID | Sev | Area | One-line | Status |
|---|---|---|---|---|
| [A2-01](#a2-01) | **High** | Timer / save | Stop or Pause while *paused* zeroes the clock; the BUG-26 retry path, edit mode and the draft checkpoint all sit on it → a retried save stores `duration 0` | fixed |
| [A2-02](#a2-02) | Medium | Streak UI | Home and the datasource use different "can rest today" rules → dead **Mark Rest Day** button after every rest day, after deleting today's workout, after finishing a stale draft | fixed |
| [A2-03](#a2-03) | Medium | Draft × streak | Finishing a draft started yesterday dates the workout yesterday but credits the streak to today; calendar, History, "Longest run" and the streak disagree | fixed |
| [A2-04](#a2-04) | Low | Draft | Timer **Reset** is never checkpointed; a kill after Reset resumes at the value the user just reset | fixed |
| [A2-05](#a2-05) | Low | Home | **Discard** on the draft banner has no failure path: a failed delete throws out of the tap handler, banner stays, no message | fixed |
| [A2-06](#a2-06) | Low | Home | Banner age goes negative if the clock moves backwards ("-30 min ago") | fixed |
| [A2-07](#a2-07) | Low | Tests | Three tests that cannot fail: BUG-12 `identical()` (sqflite single-instances per path), the placeholder, and — on a UTC machine — both DST tests | fixed (2 of 3) |
| [A2-08](#a2-08) | Suspicion | Invariants | Unenforced: one draft at a time; `status` domain; `getDraft` failure silently starts a fresh session | filed |
| [§3](#3-doc-vs-code) | — | Docs | Nine statements in `project_context.md` / `WALKTHROUGH.md` / a code comment contradict the code | listed |
| [§4](#4-checked-and-found-sound) | — | — | Everything else on the brief's list, with the test that now pins it | — |

Nothing Critical. The High is a data-corruption path on retry after a failed save — the exact path BUG-26 was meant to make safe.

---

## 1. Findings

### <a name="a2-01"></a>A2-01 — Stop/Pause from the paused state zeroes the stopwatch; three new paths depend on it

| Field | Content |
|---|---|
| **Severity** | **High** — wrong duration persisted; reachable from the normal UI |
| **Location** | `workout_timer_bloc.dart` `_onStopped` (`state is Running ? seconds : 0`), `_onPaused` (same) · `active_screen.dart` `_saveAndFinish` (dispatches `WorkoutTimerStopped` *before* the save) · `_ActiveBody` checkpoint listener (persists `Stopped(0)`) |

**Symptom**
1. Edit a workout (clock seeded **paused** at 25:00). Save fails (disk error). Snackbar says retry. The clock now reads **00:00**. Retry → the workout is stored with `duration_seconds = 0`. The original 1500 s is gone.
2. Same for a session whose stopwatch the user paused before Finish.
3. Without any failure: Pause at 12:34, then Stop → **00:00**, and the checkpoint listener writes `duration_seconds = 0, paused = 1` to the draft. Kill the app → resume at 00:00.

**Root cause**
`_onStopped`/`_onPaused` only know how to read seconds from `WorkoutTimerRunningState`; from `WorkoutTimerPausedState` they emit 0. Pre-existing code, but before this round nothing stopped a paused timer programmatically. Round 2/3 added three callers that do: `_saveAndFinish` stops unconditionally, edit mode seeds paused, and the checkpoint listener persists whatever Stopped emits. A double-tap on Pause also lands in `_onPaused` while paused → `Paused(0)`.

**Repro** — `workout_timer_bloc_test.dart` "stop while paused keeps the reading; double pause is a no-op" (bloc: `Paused(0)` instead of `Paused(754)`) · `active_screen_test.dart` "save fails → retry still saves the original duration" (screen: `25:00` gone after the failed save; retry stores 0).

**Fix**
- `_onStopped`/`_onPaused` read seconds from Running **or** Paused; Pause while not running is a no-op.
- `_saveAndFinish` no longer stops the timer. The duration is read once; on success the route is disposed and the bloc closes (subscription cancelled); on failure the clock keeps running and a retry saves the then-current reading — the true elapsed. This also removes the `Stopped(n)` checkpoint racing the finish upsert.

**Blast radius** — timer bloc (two handlers), one line in `_FinishButton`. Behaviour change: after a failed save the stopwatch keeps running instead of freezing.

### <a name="a2-02"></a>A2-02 — Two rules for "can I mark a rest day today"

| Field | Content |
|---|---|
| **Severity** | Medium — dead button; every user hits it on every rest day |
| **Location** | `home_screen.dart` gate `restDays > 0 && streak > 0 && !trainedToday` (trainedToday from the *workouts table*) · `streak_local_datasource.dart` `markRestDay` guards (alive, no workout today, no rest today, tokens — from *prefs*) |

**Symptom** — Mark a rest day. Button re-renders as "Mark Rest Day (1 left this week)". Tap → nothing (datasource: already rested today). Also: delete today's workout → button appears, tap → nothing (prefs still say trained today). Also: finish a stale draft (A2-03) → same.

**Root cause** — The rule lives in the datasource; Home re-derives an approximation from a different data source and omits the "already rested today" guard entirely.

**Repro** — `home_screen_test.dart` "Mark Rest Day disappears once a rest day is marked; button and guard agree" (real datasource behind the bloc; button still present after marking).

**Fix** — Datasource exposes `canMarkRestDay()` (the exact guard `markRestDay` applies); `GetStreak` returns `(streak, restDays, canRestToday)`; `StreakLoadedState.canRestToday`; Home's gate is `restDays > 0 && canRestToday`. One rule, one owner. Home no longer computes `trainedToday`.

**Blast radius** — `StreakLocalDatasource`, `StreakRepository`, impls, `GetStreak`, `StreakBloc`/state, Home, both fakes.

### <a name="a2-03"></a>A2-03 — A stale draft is dated from its start but the streak is credited to the finish day

| Field | Content |
|---|---|
| **Severity** | Medium — streak and calendar disagree; a later real workout the same day does not count |
| **Location** | `workout_bloc.dart` `_onFinished`: `saveWorkout(workout /* date = startedAt */)` then `updateStreak()` (= today) |

**Symptom** — Start Monday 18:00, forget to finish. Tuesday: resume, finish. History/Calendar/"Longest run": Monday. Streak: `last_workout_date = Tuesday`. Train again Tuesday evening → "second workout today", no increment. Calendar shows two training days, the streak counted one. Tuesday's Home also hides/dead-buttons Mark Rest Day (A2-02).

**Root cause** — BUG-06's decision (date = session start) was applied to the row but not to the streak side-effect.

**Repro** — `workout_bloc_test.dart` "finishing a draft started yesterday credits the streak to yesterday, not today" (real streak datasource; `last_workout_date` is today).

**Fix** — `updateStreak(on: workout.date)`. The datasource evaluates continuity *at that day*:
- same day as, or before, the last workout day → no-op (already counted / historical);
- alive iff `civilDaysBetween(lastStreakDay, day) <= 1` — negative gaps are allowed: if `lastStreakDay` is *after* the day being credited, every day between the last workout and `lastStreakDay` is a rest day that was itself verified alive when marked, so the chain through `day` is continuous;
- `last_workout_date = day`; `last_streak_day = max(existing, day)` — never moved backwards.
Worked example (the brief's "mark a rest day, then finish yesterday's draft"). Note the literal version — rest *today* with the last credited workout two days ago — is unreachable: `markRestDay` refuses a gap of 2. The reachable chain is Mon train, Tue rest, Wed rest, then on Wed finish Tuesday's draft → count 2, `last_workout = Tue`, `last_streak_day = Wed`, both tokens stay burned. Correct: trained, trained, rested. (My first draft of this test used the unreachable version and the datasource refused it — filed here so the next reader does not repeat it.)

**Blast radius** — streak interface/impl/datasource, `UpdateStreak`, `WorkoutBloc`, fakes. `StreakBloc.StreakUpdated` (unused by any screen) keeps today. Overrule if you want the streak credited to the *finish* day instead — then the row date should move too.

### <a name="a2-04"></a>A2-04 — Timer Reset is not checkpointed

| Field | Content |
|---|---|
| **Severity** | Low |
| **Location** | `active_screen.dart` `_ActiveBody` checkpoint `listenWhen` — matches Paused/Stopped/Running, not `WorkoutTimerInitialState` |

**Symptom** — Stop at 12:34 → draft says 754/paused. Reset → clock 00:00, draft still 754. Kill → resume shows 12:34 paused. **Fix** — Initial state checkpoints `(0, paused: true)`. The listener never fires for the bloc's construction state, so a fresh session writes nothing extra.

### <a name="a2-05"></a>A2-05 — Home Discard has no failure path

`_discardDraft` awaits `DiscardDraft` with no `try`; a throwing delete becomes an unhandled exception in a tap handler (red box in debug, silent in release), banner stays. **Fix** — catch, snackbar "Could not discard draft", banner stays.

### <a name="a2-06"></a>A2-06 — Banner age can be negative

`_ago` uses `now - startedAt` unclamped; a clock set backwards renders "-30 min ago". **Fix** — clamp at zero.

### <a name="a2-07"></a>A2-07 — Tests that catch nothing

1. **`concurrent first access opens the database once (BUG-12)`** asserts `identical(db1, db2)`. sqflite's factory is `lock.synchronized` and single-instances per path (`sqflite_common` `factory_mixin.dart:74,94`), so two concurrent `openDatabase` calls return the same object with or without the `??=` fix. It passes against the pre-fix code. BUG-12 was never reachable on sqflite; the fix is harmless. **Replaced** with "a failed open is not cached: the next caller retries", which exercises the branch the class actually adds (the `catchError` reset).
2. **`test/widget_test.dart`** `expect(true, isTrue)`. **Deleted.**
3. **Both DST tests** (`civilDaysBetween` pair, `longestRun` pair) are meaningful only in a DST zone; this machine is `EDT`, a UTC CI would pass them against the old `inDays` code. Not fixable in-process (Dart tests cannot set the zone); noted in the test comment already. Left as is.

Everything else asserts a behaviour that a plausible regression would break; the per-test list is in §4.

### <a name="a2-08"></a>A2-08 — Unenforced invariants (suspicions, not reproduced as user-visible bugs)

- **One draft at a time.** No constraint; the only creator is `_onStarted` when `getDraft()` returns null. If `getDraft()` *throws* (logged via `addError`), the bloc starts a fresh session with a new id; once the DB recovers, the first mutation writes a second draft row. `getDraft` `LIMIT 1 ORDER BY date DESC` then hides the older one forever (not in History, not in the banner). Enforcement would be a partial unique index (`WHERE status = 'draft'`) — a v4 step — or making `_onStarted` fail loudly instead of falling through. Left as filed: the trigger is a DB read failure on a local SQLite file.
- **`status` domain.** No `CHECK (status IN ('done','draft'))`; a typo in a future writer silently hides rows. Needs a table rebuild.
- **"`sequential()` makes the draft on disk always the latest"** (WALKTHROUGH §3) is true but for a different reason than stated: `sequential()` is per event type, so `ExerciseAdded` and `SetLogged` still interleave; ordering holds because every handler emits *before* its first `await` and sqflite executes on one FIFO connection. Documented here so the next person does not "fix" the transformer.
- **Validation caps compare display units** (`maxWeight = 2000` is 2000 lbs or 2000 kg depending on the toggle). Sanity cap only.

---

## 2. Interactions the brief asked about

| Case | Result |
|---|---|
| Edit while a draft is open | Sound. Edit state has `editing != null`; every mutation skips `_persist`; `WorkoutElapsedUpdated` returns early; Finish → `updateWorkout` on the edited id. The draft row is untouched and the banner shows it after `go('/')` (`didPopNext`). Pinned by existing bloc tests + `router_test` "finishing…". |
| Resume yesterday's draft, finish | **A2-03** (fixed). Date = start day; streak now credited to the same day. |
| Delete the workout an edit is open on | Unreachable: the edit route sits above History in a single Navigator; leaving edit pops through the confirm dialog to Home. If it ever became reachable, `updateWorkout` is `INSERT OR REPLACE` and would resurrect the row — noted. |
| Mark rest day, then finish yesterday's draft | Only reachable when the streak is already bridged by rest days (see A2-03 worked example). Was: rest token burned **and** streak incremented for today. Now: streak credited to yesterday, `last_streak_day` stays today, tokens stay burned. Datasource test "backdated workout inside a rest-bridged chain". |
| Draft across DST / timezone change | Sound. Dates are stored as local ISO **without offset** and parsed back as local, so the civil day the user saw is preserved across a zone change; elapsed is state, not wall-clock; the only wall-clock derivation is the banner's "started N ago" (cosmetic, A2-06). |

---

## 3. Doc vs code

Where they disagree the code wins; each is a stale claim, not a code bug.

| Doc | Claim | Code |
|---|---|---|
| `project_context.md` §3.3 | "there is no draft/resume-workout feature" | Feature A exists (§1 of the same doc says so) |
| §3.3 | `HistoryRequested` / `WorkoutHistoryState` "never dispatched (see §7)" | deleted in Stage 5 |
| §3.2 tree comment | `workout_database.dart` "v2 schema" | v3 |
| §4.2 | "thisWeek (rolling 7-day window)", "bestStreak" | ISO week; "Longest run" |
| §4.4 | "router gives this route a `UniqueKey()`" | removed (BUG-13) |
| §5.2 | JSON codec "currently dead code" | deleted |
| §6.1 | "Six use cases" | thirteen |
| §7.1 | "39 unit/bloc tests" | 90 → 104 after this round |
| `active_screen.dart:105` comment | timer seeded with "wall-clock delta for a resumed draft" | persisted `elapsedSeconds` (round 2) — fixed in this round |
| `WALKTHROUGH.md` §7 | "Bundle fonts (BUG-21)" as next; "CHECK constraints — a v3 step" | done; v3 is `timer_paused`, CHECK would be v4 |
| `FIXES.md` round 3 | "Nothing remains broken that I know of" | A2-01..03 were reachable from the UI |

`project_context.md` §3.3/§4.2/§4.4/§5.2/§6.1/§7.1 corrected in place (one line each); the rest are listed here only.

---

## 4. Checked and found sound

**Migration ladder.** `_onUpgrade(1→3)` applies both `if` blocks in one call — a ladder, not a hop. Proven twice: v1 file → v3 (`status` **and** `timer_paused` present, legacy rows readable), and — new this round — v2 file → v3 (step 2 must **not** re-run: "duplicate column name: status" would abort the transaction; an open v2 draft survives with `timerPaused=false`). `_createDB` produces the same columns/defaults a migrated file has. The integration suite seeds a v1 file on both platforms.

**Routing restructure.** `router_test.dart` (new): fresh install redirects `/`, `/active`, `/history`, `/calendar` to onboarding and stays after completion; `WidgetsBinding.handlePopRoute()` from `/active` reaches `PopScope` (app does not exit), shows the snackbar, and Home rebuilds with the draft banner — i.e. `RouteObserver.didPopNext` fires for a declarative `go('/')` (the top exiting page is `markForPop` under `DefaultTransitionDelegate`); Finish → Home lists the new workout. The previous round asserted the last two only on a device and the integration test did not actually check the Home refresh.

**Draft invisibility.** One read path (`status = 'done'`); all five aggregates asserted from the ffi datasource (existing). Draft ↔ done flip in place, no second row (existing).

**Write ordering under `sequential()`.** See A2-08 third bullet — correct, differently argued.

**kg-canonical boundary.** Every render goes through `formatWeight`; the single parse site converts with the unit the field is labelled in; edit carries stored doubles untouched (existing bit-identical test). The only window where a typed value could be misread is before `SettingsLoaded` resolves (one microtask) and the label reads "kg" then too.

**Error paths.** Checkpoint failure → `addError`, in-memory state authoritative, next mutation retries a full snapshot (design; a kill in that window loses ≤ the failed writes — documented). Edit-save failure → recoverable (after A2-01). Delete failure → snackbar, list unchanged, `mounted` guarded. Discard failure → A2-05.

**The four "untested" areas from round 3.** `CalendarScreen`: the reason ("only logic is in domain") was wrong — the UTC-day → local-key translation is in the screen; now pinned by `calendar_screen_test.dart`. Redirect: harness was cheap (`registerBlocFactories`); fresh-install case now covered. `StreakBloc`: reason holds (three pass-throughs; prefs cannot throw). Rest-sheet auto-close: the reason ("timing-dependent") is weak — widget tests run on a fake clock — but the bloc transition is tested and the risk is UI-only; left untested.

**Per-test blind-spot review (all 90).** Besides A2-07: `gap of exactly one day (trained yesterday) increments` is a strict subset of `consecutive days increment` (harmless duplicate). The rest each fail under a plausible regression.

---

## 5. Verification (executed, not asserted)

- `flutter analyze` → `No issues found!`
- `flutter test` → **`+105: All tests passed!`** (was 90; −1 placeholder, +16)
  - datasources **42** (streak 29 · workout on real SQLite 13)
  - repositories **3** · domain stats **8**
  - blocs **25** (Workout 13 · WorkoutTimer 8 · RestTimer 4)
  - screens **19** (Active 8 · Home 6 · History 2 · Onboarding 2 · Calendar 1)
  - router **3** · widgets **2** · units/settings **3**
- Android emulator (Pixel 9 Pro XL, Android 17), `integration_test/app_flow_test.dart` from a seeded v1 DB → `00:27 +1: All tests passed!`
- iOS simulator (iPhone 17 Pro, iOS 26.3), same file → `00:30 +1: All tests passed!`
- One run per platform, at the end, after all four fix commits.

**Commits (severity order, one per cluster):** `b0e31cf` audit + confirmation tests · `d11e187` A2-01/04 timer · `628e16f` A2-02/03 streak · `8100ebc` A2-05/06 Home · docs.

## 6. Still open, unverified, or judgment calls

- **A2-03 policy** — the streak is now credited to the workout's *start* day. If you would rather credit the finish day, the row's date should move with it; say so and it is a two-line change in `_toWorkout`/`_onFinished`.
- **A2-07 DST tests** are meaningful only on a machine in a DST zone (this one is). A UTC CI would not catch a regression of BUG-03. Not fixable in-process.
- **A2-08** is filed, not fixed: no constraint enforces one draft / the `status` domain, and a `getDraft()` read failure still starts a fresh session silently. Both need a v4 schema step or a design decision.
- **Rest-sheet auto-close** still has no widget test (bloc transition is tested).
- **Not device-verified this round:** the A2-01 retry path and the A2-02 button change were verified by widget tests with real blocs/datasource, not by injecting a disk failure on a device. The device suites cover the unchanged happy path.
- **Spend** — I have no console access from this session; the number below is a token-volume estimate. Raw estimate for round 4 ≈ **$22** (two device builds, ~30 tool calls, ~3k lines read). Applying the ~40 % over-estimate you measured on previous rounds → **≈ $15**. Cumulative across all rounds by the same method: ≈ $134 raw / ≈ $95 calibrated. Please read the real figure from the console; the $85 stop was not approached.
