# Walkthrough — how the changed pieces work, and why

Written for: the repo owner, to defend each decision in a technical interview.

## 1. Streak date arithmetic (`domain/streak_rules.dart`, `StreakLocalDatasourceImpl`)

**The bug.** `a.difference(b).inDays` divides *elapsed physical time* by 24 h. Two local midnights across a DST spring-forward are 23 h apart, so `inDays` is 0 and "yesterday" reads as "today". Day-truncating the operands does not help — it is the *distance* that is wrong, not the operands.

**The fix.** `civilDaysBetween(a, b)` projects both dates onto UTC (`DateTime.utc(y, m, d)`) before subtracting. UTC has no DST, so every day is exactly 24 h by construction. The UTC values are arithmetic scaffolding; nothing displays or stores them. `startOfWeek` is built the same way — `DateTime(y, m, d - (weekday - 1))` — because `subtract(Duration(days:))` across a DST boundary lands an hour off midnight, and the constructor normalises day ≤ 0 into the previous month.

**Why not UTC everywhere?** "Did I train today?" is a question about the user's local calendar. A 19:00 PST workout is Tuesday to them and Wednesday in UTC. Local civil dates, UTC arithmetic.

**Why not a day-ordinal integer in storage?** Cleaner in principle, but a storage-format change with an opaque value when you inspect prefs. Fixing the arithmetic keeps the stored ISO date readable.

**Semantics (now stated in one place).** A streak is consecutive civil days each of which is a workout or an explicitly-marked rest day; it increments once per *training* day; a rest day bridges but does not increment. `last_workout_date` is only ever written by a workout. `last_streak_day` carries continuity (workout or rest). The old code wrote both facts into one key, which is why "did I train today?" could not be asked — and why BUG-07 and BUG-09 existed. A lapsed streak reads as 0 via `_isAlive`, rather than showing a stale count until the next workout.

**Week.** ISO Monday week, derived from the calendar rather than from "when the app was last opened", so it cannot drift (the old `>= 7` window re-anchored to *today*, so a day-8 open produced an 8-day week). `kRestDaysPerWeek` lives in `domain/` because both `data/` and `presentation/` may import domain — putting it in the datasource would force Home to import data, violating the dependency rule.

**Testability.** `DateTime.now()` inside the datasource made every branch untestable. The clock is a constructor parameter (`clock: () => fixedDate`), `SharedPreferences.setMockInitialValues({})` is the in-memory store. 21 tests drive the exact dates: consecutive, gap 1, gap > 1, same-day double, rest-then-workout, week rollover at 6/7/8, and the DST pair `2025-03-09 → 03-10`.

**What breaks if the boundary is crossed.** If `home_screen.dart` imported `StreakLocalDatasourceImpl` for the constant, presentation would depend on a concrete data class; swapping the datasource (e.g. to SQLite-backed rest-day rows for BUG-09's reconciliation) would ripple into a widget.

## 2. Migration path (`WorkoutDatabase`)

**Mechanics.** `openDatabase` compares on-disk `PRAGMA user_version` to `version:`. New file → `onCreate`. Lower → `onUpgrade(old, new)`. Higher → `onDowngrade`. With `onUpgrade` null, sqflite throws `ArgumentError` — it does not fall back to `onCreate` — so bumping the version bricked every existing install.

**Shape.** A forward-only ladder: `if (oldVersion < 2) {…}`, `if (oldVersion < 3) {…}`. Not a `switch`: a user going v1 → v4 must apply every step in order. sqflite runs `onUpgrade` inside a transaction, so a failing step rolls back atomically. `_createDB` must produce the same shape a fully-migrated DB has — the classic divergence bug is a fresh install and a migrated install disagreeing.

**`onConfigure`.** `PRAGMA foreign_keys` is a documented no-op inside a transaction (proved: `fk=0` before and after `COMMIT`). `onCreate`/`onUpgrade` run in one, so the pragma there is dead. `onConfigure` runs on every open, before and outside that transaction — the only hook where it takes effect, *including during migrations*. Per-connection, so it must run every open, not once.

**v2 step.** `ALTER TABLE workouts ADD COLUMN status TEXT NOT NULL DEFAULT 'done'`. The default backfills correctly because every pre-existing row is a finished workout. Weight rows stay in kg (owner decision; the app was only ever used in kg), so no data migration.

**Downgrade.** `onDatabaseDowngradeDelete`: single-user, local, no sync — an unlaunchable app is worse than a wiped one. Approved.

**Verified twice.** `workout_local_datasource_test.dart` builds a v1 file by hand and opens it through `WorkoutDatabase` under ffi; the integration test seeds a v1 file on the simulator and walks the UI against it.

## 3. Event transformer (`StreakBloc`, `WorkoutBloc`)

**Mechanics.** bloc 8.x's default transformer is `concurrent()` (bloc.dart:62). Two `RestDayMarked` events dispatched in one frame run their handlers *interleaved at every `await`*. `markRestDay` is read-guard → await → read counter → await → write: handler B can read the guard before A has written it, so both compute `2 − 1` and both write `1` — a lost update.

**Fix, two layers.** `sequential()` from `bloc_concurrency` queues events per handler so the second cannot start until the first completes. *And* the datasource writes its same-day guard *first*, so any future caller that is not serialised still cannot double-decrement. The transformer fixes this call site; the write order fixes the class of bug.

**Why the package.** A hand-rolled `_busy` latch is the same idea with more failure modes (must reset on every error path, invisible to the event stream). `bloc_concurrency` is first-party and ~100 lines.

**WorkoutBloc.** Mutation handlers became read-emit-await-persist. Under `concurrent()`, two fast taps could persist an *older* snapshot after a newer one. `sequential()` on the four mutation events makes the draft on disk always the latest emitted state.

## 4. Feature A — persisted draft: state machine

`WorkoutInitialState → WorkoutLoadingState → WorkoutInProgressState{id, startedAt, exercises, editing?} → (WorkoutCompleteState | WorkoutErrorState → WorkoutInProgressState)`; `WorkoutDiscarded` returns to `Initial`.

**Why a Loading state.** `WorkoutStarted` must look up the draft before it knows whether to create or resume. Without `Loading`, the screen renders "Add Exercise" for an empty session and then swaps to a resumed one — visible flicker, and a tap in that window would mutate the wrong session. A sealed hierarchy makes the screen *exhaustively* handle it; a single class with nullable fields would let `exercises == null && isLoading == false` exist.

**Why `id` and `startedAt` are in the state.** The draft row and the finished row share the id, so finishing is one `INSERT OR REPLACE` that flips `status` — never a draft *and* a copy. `startedAt` is the workout's date (BUG-06); the timer resumes from the *persisted* `elapsedSeconds`, never from wall-clock age (§4, Stopwatch persistence).

**Why write-through, not `AppLifecycleState`.** `paused` does not fire when the OS kills the process; `detached` cannot be awaited. Persisting on every mutation is the only strategy that covers backgrounding, navigation *and* kill. Cost: one small transaction per tap, on a local DB.

**Why a draft is a workout row.** Reuses the tables, the cascade, and the hydrate code; no JSON blob and no codec. `getWorkouts` filters `status = 'done'`. The replace-cascade path the audit flagged as a trap is now used on purpose — and is safe only because `onConfigure` guarantees FKs.

**Stopwatch persistence (round 2/3).** Elapsed is *state*, not `now − startedAt`: `elapsedSeconds` + `timerPaused` on `WorkoutInProgressState`, checkpointed by a `BlocListener<WorkoutTimerBloc>` every 10 s, on pause/stop, and on the pause→running edge, via `RecordDraftElapsed` (a single-column `UPDATE`, not a full replace). Resume seeds `WorkoutTimerStarted(from: elapsed, paused: timerPaused)`, which emits `WorkoutTimerPausedState` directly and creates no subscription — so a session that died paused resumes paused and accrues nothing. *Stopped* is persisted as paused for the same reason. Schema v3 carries `timer_paused`. Snapshot audit: rest-timer countdown (seconds-scale, dropped), unsubmitted text and open forms (UI-only), weight unit (separate pref) — none change what the user sees on resume.

**Failure.** Draft write fails → `addError` (observer logs it), in-memory state stays authoritative, next mutation retries with a full snapshot. Finish fails → `Error` then straight back to `InProgress` so the mutation handlers (which gate on `InProgress`) accept the user's fix (BUG-26).

**Boundary.** The bloc knows `SaveDraft`/`GetDraft`, not `status = 'draft'`. If it imported the datasource to write the status string itself, the "one row, two statuses" design would leak into presentation and could not be changed without touching the bloc.

## 5. Feature B — edit/delete: state machine

Same states; `WorkoutInProgressState.editing: Workout?` is the mode flag. `WorkoutEditStarted(w)` seeds `id`, `startedAt = w.date`, `exercises`. Mutations skip `_persist` when editing. `WorkoutFinished` in edit mode calls `UpdateWorkout` — never `SaveWorkout` — and never `updateStreak`.

**Why a flag on the state, not a second bloc/screen.** Create and edit differ in three decisions (persist? which use case on finish? bump streak?), all of which the bloc already owns. Parameterising the *state* reuses the whole screen; a second bloc would duplicate five handlers.

**Why `UpdateWorkout` is its own use case** when its SQL equals `saveWorkout`: the use-case layer is where policy lives. "An edit is not a training event" is a rule; encoding it as a distinct entry point means a future caller cannot bump the streak by accident. Same argument for `DiscardDraft` vs `DeleteWorkout`.

**Delete.** `DELETE FROM workouts WHERE id = ?`; children go via `ON DELETE CASCADE` — the first time it fires in this app. Confirmed on real SQLite under ffi and on the simulator.

**Failure.** Delete fails → snackbar, list unchanged. Update fails → same recovery path as BUG-26. Abandoning an edit (back → confirm) leaves the original row untouched because edits never write.

**Judgment call to revisit.** History still reads via `FutureBuilder` and calls `DeleteWorkout` directly. It matches the screen's existing read path and cost nothing extra; the next refactor is a `HistoryBloc` so History, Home and Calendar share one source of truth instead of three `GetWorkouts` calls.

## 6. Android vs iOS (what the emulator forced)

**System back exited the app from `/active`.** go_router 13's `popRoute` (`delegate.dart:59`) nulls the navigator when `canPop()` is false and never calls `maybePop`, so a `PopScope` on a *root* route is bypassed and Flutter falls through to `SystemNavigator.pop()`. `/active` was always a root route because Home used `go()`. Fix: `/active` is a child route of `/`, so `go('/active')` builds `['/', '/active']` and the gesture reaches `PopScope`. Consequence: Home persists beneath and is no longer recreated on finish — it subscribes to a `RouteObserver` and reloads in `didPopNext` (workouts, draft banner, streak). iOS never surfaced this: no system back.

**Edit mode ran the clock.** Same class as the pause flag: the saved duration was seeded into a *running* timer, so a short edit would save a longer workout. Edit mode seeds paused.

**Status-bar icons** were light on the cream AppBar (iOS infers contrast; Android needs `systemOverlayStyle`).

`flutter test integration_test/…` on Android **reinstalls the APK on every run, wiping app data** (observed: run 2 of the same entrypoint printed `Installing …app-debug.apk` and the prefs marker was gone). Cross-launch persistence therefore cannot be asserted through that harness; the process-death check is done against a real debug build driven by `adb` with `am force-stop`. The flow suite itself passed unchanged on Android 17 — the v1→v3 ladder on `sqflite_android`, keyboard insets on the log-set row and rest sheet, and every bundled font weight. No platform conditional was needed in `lib/`.

## 7. What I'd do next

`HistoryBloc` (above). Rest days as rows so "Longest run" and the streak card can share one definition (BUG-09 reconciliation) and the calendar can draw real rest-day markers. Bundle fonts (BUG-21). `CHECK (reps > 0)` constraints — needs a table rebuild, so a v3 step.
