# Walkthrough — how the changed pieces work, and why

Written for: the repo owner, to defend each decision in a technical interview.

## 1. Streak date arithmetic (`domain/streak_rules.dart`, `StreakLocalDatasourceImpl`)

**The bug.** `a.difference(b).inDays` divides *elapsed physical time* by 24 h. Two local midnights across a DST spring-forward are 23 h apart, so `inDays` is 0 and "yesterday" reads as "today". Day-truncating the operands does not help — it is the *distance* that is wrong, not the operands.

**The fix.** `civilDaysBetween(a, b)` projects both dates onto UTC (`DateTime.utc(y, m, d)`) before subtracting. UTC has no DST, so every day is exactly 24 h by construction. The UTC values are arithmetic scaffolding; nothing displays or stores them. `startOfWeek` is built the same way — `DateTime(y, m, d - (weekday - 1))` — because `subtract(Duration(days:))` across a DST boundary lands an hour off midnight, and the constructor normalises day ≤ 0 into the previous month.

**Why not UTC everywhere?** "Did I train today?" is a question about the user's local calendar. A 19:00 PST workout is Tuesday to them and Wednesday in UTC. Local civil dates, UTC arithmetic.

**Why not a day-ordinal integer in storage?** Cleaner in principle, but a storage-format change with an opaque value when you inspect prefs. Fixing the arithmetic keeps the stored ISO date readable.

**Semantics (now stated in one place).** A streak is consecutive civil days each of which is a workout or an explicitly-marked rest day; it increments once per *training* day; a rest day bridges but does not increment. `last_workout_date` is only ever written by a workout. `last_streak_day` carries continuity (workout or rest). The old code wrote both facts into one key, which is why "did I train today?" could not be asked — and why BUG-07 and BUG-09 existed. A lapsed streak reads as 0 via `_isAlive`, rather than showing a stale count until the next workout.

**Week.** ISO Monday week, derived from the calendar rather than from "when the app was last opened", so it cannot drift (the old `>= 7` window re-anchored to *today*, so a day-8 open produced an 8-day week). `kRestDaysPerWeek` lives in `domain/` because both `data/` and `presentation/` may import domain — putting it in the datasource would force Home to import data, violating the dependency rule.

**Testability.** `DateTime.now()` inside the datasource made every branch untestable. The clock is a constructor parameter (`clock: () => fixedDate`), `SharedPreferences.setMockInitialValues({})` is the in-memory store. 29 tests drive the exact dates: consecutive, gap 1, gap > 1, same-day double, rest-then-workout, week rollover at 6/7/8, backdated credit (`updateStreak(on:)`), and the DST pair `2025-03-09 → 03-10`. The DST cases set `TZ=America/New_York` inside the process (`test/helpers/tz.dart`, libc `setenv` + `tzset`) and assert the 23 h gap is really there, so they fail against the old `inDays` arithmetic on any host — verified by patching it back in under `TZ=UTC`.

**What breaks if the boundary is crossed.** If `home_screen.dart` imported `StreakLocalDatasourceImpl` for the constant, presentation would depend on a concrete data class; swapping the datasource (e.g. to SQLite-backed rest-day rows for BUG-09's reconciliation) would ripple into a widget.

## 2. Migration path (`WorkoutDatabase`)

**Mechanics.** `openDatabase` compares on-disk `PRAGMA user_version` to `version:`. New file → `onCreate`. Lower → `onUpgrade(old, new)`. Higher → `onDowngrade`. With `onUpgrade` null, sqflite throws `ArgumentError` — it does not fall back to `onCreate` — so bumping the version bricked every existing install.

**Shape.** A forward-only ladder: `if (oldVersion < 2) {…}`, `if (oldVersion < 3) {…}`. Not a `switch`: a user going v1 → v4 must apply every step in order. sqflite runs `onUpgrade` inside a transaction, so a failing step rolls back atomically. `_createDB` must produce the same shape a fully-migrated DB has — the classic divergence bug is a fresh install and a migrated install disagreeing.

**`onConfigure`.** `PRAGMA foreign_keys` is a documented no-op inside a transaction (proved: `fk=0` before and after `COMMIT`). `onCreate`/`onUpgrade` run in one, so the pragma there is dead. `onConfigure` runs on every open, before and outside that transaction — the only hook where it takes effect, *including during migrations*. Per-connection, so it must run every open, not once.

**v2 step.** `ALTER TABLE workouts ADD COLUMN status TEXT NOT NULL DEFAULT 'done'`. The default backfills correctly because every pre-existing row is a finished workout. Weight rows stay in kg (owner decision; the app was only ever used in kg), so no data migration.

**Downgrade.** `onDatabaseDowngradeDelete`: single-user, local, no sync — an unlaunchable app is worse than a wiped one. Approved.

**v4 step (round 6): a table rebuild inside the transaction.** A `CHECK` cannot be added with `ALTER TABLE`, and the standard rebuild recipe (`DROP TABLE` old, rename new) is a trap here: with foreign keys ON, `DROP TABLE` on a parent performs an implicit `DELETE` that **cascades into the children**, and `PRAGMA foreign_keys = OFF` is a no-op inside the upgrade transaction where `onUpgrade` runs. So the rebuild goes the other way round: rename the three old tables away, create the new ones with the *same* DDL `_createDB` uses (one definition of the shape, so a fresh install and a migrated file cannot drift — a test asserts their `PRAGMA table_info` and index lists are identical), copy the rows, drop the old set children-first so nothing cascades, backfill `name_key` from Dart, then create the indexes. The step also de-duplicates any pre-v4 second draft (keeps the newest, the one `LIMIT 1` showed) so the partial unique index can be created.

**Ladder semantics tightened.** Step N now runs iff `oldVersion < N && newVersion >= N`. For the app that is the same as before (`newVersion` is always the latest); for tests it means one hop can be driven at a time on a hand-built file. `migration_test.dart` walks v1→v2, v2→v3, v3→v4 individually and v1→v4 through the app's opener. A suite that only walks the full chain stays green while a middle step rots.

**Verified.** Every hop under ffi; the integration test seeds a v1 file on both the emulator and the simulator and walks the UI against the migrated v4 file — including the rebuild on the real plugin.

## 3. Event transformer (`StreakBloc`, `WorkoutBloc`)

**Mechanics.** bloc 8.x's default transformer is `concurrent()` (bloc.dart:62). Two `RestDayMarked` events dispatched in one frame run their handlers *interleaved at every `await`*. `markRestDay` is read-guard → await → read counter → await → write: handler B can read the guard before A has written it, so both compute `2 − 1` and both write `1` — a lost update.

**Fix, two layers.** `sequential()` from `bloc_concurrency` queues events per handler so the second cannot start until the first completes. *And* the datasource writes its same-day guard *first*, so any future caller that is not serialised still cannot double-decrement. The transformer fixes this call site; the write order fixes the class of bug.

**Why the package.** A hand-rolled `_busy` latch is the same idea with more failure modes (must reset on every error path, invisible to the event stream). `bloc_concurrency` is first-party and ~100 lines.

**WorkoutBloc.** Mutation handlers became read-emit-await-persist. Under `concurrent()`, two fast taps could persist an *older* snapshot after a newer one. `sequential()` is applied to each mutation event — but note what it does and does not do. **It is a queue per event type**, not a global one: a `SetLogged` still runs while an `ExerciseAdded` is awaiting its write. The on-disk draft is nevertheless always the latest emitted state, for two other reasons: (1) every handler reads `state` and `emit`s *before* its first `await`, so the snapshot each handler persists is the newest state at the moment it started, in dispatch order; (2) sqflite executes statements on one connection in FIFO order, so writes land in that same order. `sequential()` only adds that two events *of the same type* cannot interleave. An earlier version of this section credited the transformer with the whole guarantee; that was wrong, and "fixing" it by swapping the transformer would change nothing — see `AUDIT_2.md` A2-08.

## 4. Feature A — persisted draft: state machine

`WorkoutInitialState → WorkoutLoadingState → WorkoutInProgressState{id, startedAt, exercises, editing?} → (WorkoutCompleteState | WorkoutErrorState → WorkoutInProgressState)`; `WorkoutDiscarded` returns to `Initial`.

**Why a Loading state.** `WorkoutStarted` must look up the draft before it knows whether to create or resume. Without `Loading`, the screen renders "Add Exercise" for an empty session and then swaps to a resumed one — visible flicker, and a tap in that window would mutate the wrong session. A sealed hierarchy makes the screen *exhaustively* handle it; a single class with nullable fields would let `exercises == null && isLoading == false` exist.

**Why `id` and `startedAt` are in the state.** The draft row and the finished row share the id, so finishing is one `INSERT OR REPLACE` that flips `status` — never a draft *and* a copy. `startedAt` is the workout's date (BUG-06); the timer resumes from the *persisted* `elapsedSeconds`, never from wall-clock age (§4, Stopwatch persistence).

**Why write-through, not `AppLifecycleState`.** `paused` does not fire when the OS kills the process; `detached` cannot be awaited. Persisting on every mutation is the only strategy that covers backgrounding, navigation *and* kill. Cost: one small transaction per tap, on a local DB.

**Why a draft is a workout row.** Reuses the tables, the cascade, and the hydrate code; no JSON blob and no codec. `getWorkouts` filters `status = 'done'`, and since v4 a `CHECK` rejects any other status. The upsert is an explicit `DELETE` by id then a plain `INSERT` (round 6; it was `INSERT OR REPLACE`): the cascade on the delete recreates the children cleanly either way, but `OR REPLACE` would also "resolve" a conflict on v4's one-draft partial index by silently deleting the *other* draft, whereas a plain `INSERT` throws and leaves it intact. Safe only because `onConfigure` guarantees FKs.

**Stopwatch persistence (round 2/3).** Elapsed is *state*, not `now − startedAt`: `elapsedSeconds` + `timerPaused` on `WorkoutInProgressState`, checkpointed by a `BlocListener<WorkoutTimerBloc>` every 10 s, on pause/stop, and on the pause→running edge, via `RecordDraftElapsed` (a single-column `UPDATE`, not a full replace). Resume seeds `WorkoutTimerStarted(from: elapsed, paused: timerPaused)`, which emits `WorkoutTimerPausedState` directly and creates no subscription — so a session that died paused resumes paused and accrues nothing. *Stopped* is persisted as paused for the same reason. Schema v3 carries `timer_paused`. Snapshot audit: rest-timer countdown (seconds-scale, dropped), unsubmitted text and open forms (UI-only), weight unit (separate pref) — none change what the user sees on resume.

**Failure.** Draft write fails → `addError` (observer logs it), in-memory state stays authoritative, next mutation retries with a full snapshot. Finish fails → `Error` then straight back to `InProgress` so the mutation handlers (which gate on `InProgress`) accept the user's fix (BUG-26).

**Boundary.** The bloc knows `SaveDraft`/`GetDraft`, not `status = 'draft'`. If it imported the datasource to write the status string itself, the "one row, two statuses" design would leak into presentation and could not be changed without touching the bloc.

## 5. Feature B — edit/delete: state machine

Same states; `WorkoutInProgressState.editing: Workout?` is the mode flag. `WorkoutEditStarted(w)` seeds `id`, `startedAt = w.date`, `exercises`. Mutations skip `_persist` when editing. `WorkoutFinished` in edit mode calls `UpdateWorkout` — never `SaveWorkout` — and never `updateStreak`.

**Why a flag on the state, not a second bloc/screen.** Create and edit differ in three decisions (persist? which use case on finish? bump streak?), all of which the bloc already owns. Parameterising the *state* reuses the whole screen; a second bloc would duplicate five handlers.

**Why `UpdateWorkout` is its own use case** when its SQL equals `saveWorkout`: the use-case layer is where policy lives. "An edit is not a training event" is a rule; encoding it as a distinct entry point means a future caller cannot bump the streak by accident. Same argument for `DiscardDraft` vs `DeleteWorkout`.

**Delete.** `DELETE FROM workouts WHERE id = ?`; children go via `ON DELETE CASCADE` — the first time it fires in this app. Confirmed on real SQLite under ffi and on the simulator.

**Failure.** Delete fails → snackbar, list unchanged. Update fails → same recovery path as BUG-26 — and that path had a hole until round 4; see §6a. Abandoning an edit (back → confirm) leaves the original row untouched because edits never write.

**Judgment call to revisit.** History still reads via `FutureBuilder` and calls `DeleteWorkout` directly. It matches the screen's existing read path and cost nothing extra; the next refactor is a `HistoryBloc` so History, Home and Calendar share one source of truth instead of three `GetWorkouts` calls.

## 6a. A latent bug made reachable by three unrelated features (A2-01)

**The bug.** `WorkoutTimerBloc._onStopped` and `_onPaused` computed the reading as `state is WorkoutTimerRunningState ? seconds : 0`. From a *paused* clock, Stop emitted `Stopped(0)`. That line had been there since the first commit and nobody had noticed, because the UI only shows Stop next to a running clock... and next to a paused one, which nobody tried.

**What made it reachable.** Three additions from rounds 2–3, none of which touched the timer:
1. **BUG-26 recovery** made a failed save return to an editable state — and `_saveAndFinish` dispatched `WorkoutTimerStopped` *before* the save. So a failed save left the clock stopped, and if it had been paused, stopped at **0**. The retry then read 0 and saved it. The very path built to make save failures safe corrupted the duration.
2. **Edit mode** seeds the clock *paused* at the saved duration (round 3, so a short edit does not inflate a long workout). Every edit therefore started in the exact state that made Stop return 0.
3. **The draft checkpoint listener** persisted whatever Stopped emitted, so Pause → Stop wrote `duration_seconds = 0` into the draft; a kill afterwards resumed at 00:00.

Each addition was correct on its own terms and tested in isolation. The interaction was not, because no test ever paused a clock and then stopped it. A widget test that fails the save in edit mode and retries reproduced it in one shot.

**The fix, and why Save & Finish no longer stops the clock.** The bloc reads from Running *or* Paused, and ignores Pause when not running (a double-tap before the button swaps landed in `_onPaused` while paused → `Paused(0)`, same class). More importantly, `_saveAndFinish` now only *reads* the duration: on success the route is disposed and `close()` cancels the subscription; on failure the clock keeps running, so a retry saves the then-current reading — which is the true elapsed time. Stopping before the outcome was known was the design error; it also raced a `Stopped(n)` checkpoint against the finish upsert.

**Interview framing.** The failure mode is not "someone wrote a bad line"; it is that a precondition (“Stop is only ever sent to a running clock”) was never written down, so three later changes each violated it without knowing it existed. The remedy that scales is the one in `HANDOFF.md` §3: name the invariant, say where it is enforced, and test the interaction, not just the parts.

## 6b. Which day does a finished draft credit? (A2-03)

A session is dated from its *start* (BUG-06: a 23:50 workout finished at 00:20 belongs to the day it started). Round 2 applied that to the row but the streak side-effect still ran `updateStreak()` = *today*. Resume Monday's forgotten draft on Tuesday and the calendar said Monday while the streak said Tuesday — and a real Tuesday workout then read as "second workout today" and did not count.

**Decision: credit the training day, not the save day.** The streak counts days on which the user *trained*; tapping Finish is bookkeeping, not training. Crediting the save day would make the streak depend on when the user remembered to press a button, and would disagree with every other view of the same data (History, Calendar, "Longest run" all group by `workout.date`). So `updateStreak(on: workout.date)`.

**Mechanics for a backdated day.** Continuity is evaluated *at that day*: a day at or before the last credited workout is history (no-op); alive iff `civilDaysBetween(lastStreakDay, day) <= 1` where a negative gap is allowed — if `lastStreakDay` is after the day being credited, every day between the last workout and it is a rest day that was verified alive when marked, so the chain is continuous; and `last_streak_day` is `max(existing, day)`, never moved backwards. The datasource tests walk each case, including the one that is *not* reachable (rest today with the last workout two days ago is refused by `markRestDay` itself).

**Overrule point.** If the product decision becomes "credit the finish day", the row's date must move with it — otherwise the disagreement returns. Two lines in `_toWorkout`/`_onFinished`.

## 6. Android vs iOS (what the emulator forced)

**System back exited the app from `/active`.** go_router 13's `popRoute` (`delegate.dart:59`) nulls the navigator when `canPop()` is false and never calls `maybePop`, so a `PopScope` on a *root* route is bypassed and Flutter falls through to `SystemNavigator.pop()`. `/active` was always a root route because Home used `go()`. Fix: `/active` is a child route of `/`, so `go('/active')` builds `['/', '/active']` and the gesture reaches `PopScope`. Consequence: Home persists beneath and is no longer recreated on finish — it subscribes to a `RouteObserver` and reloads in `didPopNext` (workouts, draft banner, streak). iOS never surfaced this: no system back.

**Edit mode ran the clock.** Same class as the pause flag: the saved duration was seeded into a *running* timer, so a short edit would save a longer workout. Edit mode seeds paused.

**Status-bar icons** were light on the cream AppBar (iOS infers contrast; Android needs `systemOverlayStyle`).

`flutter test integration_test/…` on Android **reinstalls the APK on every run, wiping app data** (observed: run 2 of the same entrypoint printed `Installing …app-debug.apk` and the prefs marker was gone). Cross-launch persistence therefore cannot be asserted through that harness; the process-death check is done against a real debug build driven by `adb` with `am force-stop`. The flow suite itself passed unchanged on Android 17 — the v1→v3 ladder on `sqflite_android`, keyboard insets on the log-set row and rest sheet, and every bundled font weight. No platform conditional was needed in `lib/`.

## 8. Round 6 — A2-08 closed, Feature D built

### 8a. The draft invariants, and why the application fix landed before the schema fix

Three facts were unenforced: one draft at a time, the `status` domain, and a `getDraft()` read failure silently starting a fresh session. The order mattered. The schema fix alone — a partial unique index on `status = 'draft'` — would have converted the hidden second draft into a *write failure* on every checkpoint of a session the user was actively logging, because the only way a second draft ever arose was the bloc falling through to a fresh id after a failed read. An index with nothing safe to fail into is worse than the bug.

So first, `WorkoutBloc._onStarted` stops falling through: a failed `getDraft()` emits `WorkoutUnavailableState` and the screen offers Retry (the row is still on disk; retry re-reads it). Mutations and checkpoints are refused in that state, so no second id is ever created. Home's Discard deletes *every* draft row, not one id. `getDraft` asserts at most one row in debug. Only then the schema: `CHECK (status IN ('done','draft'))` and `CREATE UNIQUE INDEX one_draft ON workouts(status) WHERE status = 'draft'`, both in the v4 rebuild (§2). The index is now a backstop that should never fire; if it does, the failure is loud (a `DatabaseException` into `addError`) and preserves the existing draft rather than replacing it — which is why the upsert stopped using `INSERT OR REPLACE` (§4).

### 8b. Where a read model lives, and why it is not an entity

"Top set per training day for one exercise" is the first shape in the app that maps to no aggregate root. It is computed across many workouts, never written back, and its fields (`day`, `reps`, `weightKg`, `prIndex`) are what one screen needs, not what the domain stores. Three places were considered:

- *`domain/entities/` beside `Workout`* — wrong signal: entities are things the app persists and owns; this is derived and read-only, and putting it there invites someone to add a `save`.
- *`data/`* — presentation would then import a data type, which the dependency rule forbids; and the two rules over the shape (the civil-day fold, the PR ordering) are business rules, not storage details.
- *`domain/read_models/`* with its own `ProgressRepository` — chosen. Domain owns the shape and the rules; data owns the SQL that produces the raw rows; presentation renders. The separate repository keeps `WorkoutRepository` from growing report methods and states, in the type system, that this is a different access pattern: a query crossing the repository boundary without being an aggregate.

The split of work follows the same line: SQLite does the reduction it is good at (max per workout, `GROUP BY` on the key, status filter); Dart does the two rules the app must own — folding workouts into civil days with the DST-safe `civilDate` (SQLite's `date()`/`substr` would encode a *second* definition of "day"), and choosing the PR (weight first, then reps; earliest day keeps a tie). The interview answer is one sentence: *the shape lives where its rules live, and its rules are domain rules, but it is filed as a read model so nobody mistakes it for state.*

### 8c. The exercise-name key

Names are free text and the app only ever deduplicated within one session, case-insensitively — so "Bench" and "bench" in different sessions were already two exercises in the data. The rule is now one function, `normalizeExerciseName` = trim + Unicode case-fold, used by the datasource (stored `name_key`, v4, indexed), the bloc (in-session dedupe) and the progress query (grouping). A stored column rather than `COLLATE NOCASE` because SQLite's case-folding is ASCII-only and would disagree with Dart on "Über"; the v4 backfill runs in Dart for the same reason. Display name when spellings disagree: the most recent finished workout's. Deliberately no merge or rename UI — "BP" and "Bench Press" stay separate.

### 8d. What D deliberately does not do

No live "new PR" badge on save. The app has no reactive read path — every screen fetches on mount — and the badge is the one part of D that needs one. The detail screen ships as a `FutureBuilder`, the same shape as History and Calendar; the badge is first in line after `HistoryBloc`.

## 7. What I'd do next

See `HANDOFF.md` §4–5 for the current list with reasoning. In short: a reactive read path (`HistoryBloc`) first, then the live PR badge D left out; rest days as rows so "Longest run" and the streak card share one definition (BUG-09) and the calendar can draw real rest-day markers (a v5 step — v4 is the CHECK / one-draft index / `name_key` rebuild). Fonts are bundled (BUG-21, round 2).
