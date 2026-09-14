# Feature Proposals

## Four candidates

### A — Persisted in-progress workout draft
**User view.** Start a workout, log sets, get a phone call, come back an hour later (or after Android kills the process): the session is exactly where you left it, timer included. Home offers "Resume workout" instead of "Begin".
**Weakness it forces you to fix.** The in-progress workout lives only in a route-scoped BLoC. BUG-17's `PopScope` covers the back gesture; nothing covers backgrounding or process death. This is the fix.
**Surface.** Data: schema v2 (first real migration), `getDraft`, draft upsert. Domain: `SaveDraft`, `GetDraft`, `DiscardDraft` use cases. Presentation: `WorkoutBloc` writes through on every mutation, resumes on start; timer seeded from wall-clock elapsed; Home banner.
**Teaches.** Write-through persistence as the *only* strategy that survives process death (lifecycle hooks do not fire on kill); a real `onUpgrade` step; the cascade-on-replace path used deliberately.
**Effort / risk.** Medium / medium — touches the bloc's every handler.

### B — Workout edit and delete
**User view.** Long-press a history card → Delete (confirm) or Edit; Edit reopens it in the Active screen; Save writes it back in place.
**Weakness it forces.** `ON DELETE CASCADE` has never fired; `ConflictAlgorithm.replace` on the workout row is the documented trap (children survive only if FKs are off). Both get exercised under the now-guaranteed `onConfigure` pragma. First `UPDATE`/`DELETE` path in the data layer.
**Surface.** Data: `deleteWorkout`, `updateWorkout`. Domain: `DeleteWorkout`, `UpdateWorkout`. Presentation: `WorkoutEditStarted` event, `editing` flag in state, history affordances, route `extra`.
**Teaches.** Reusing one screen for create/edit by parameterising the *state*, not the widget; why update must not touch the streak (use-case boundary as policy boundary).
**Effort / risk.** Medium / low.

### C — Routine templates
**User view.** Save "Push day" as a template; start a workout pre-populated.
**Forces.** A second aggregate root with its own tables; the first many-to-many-ish read.
**Teaches.** Entity vs. template distinction; seeding state from a use case.
**Effort / risk.** Medium-high / low. Additive; fixes nothing existing.

### D — Per-exercise progress and PRs
**User view.** Tap "Bench" anywhere → chart of top set over time, PR badge.
**Forces.** A real aggregate query (`GROUP BY exercise name`), the first non-N+1 read, and a case-insensitive name key the app currently lacks.
**Teaches.** Query-shaped read models vs. entity-shaped ones.
**Effort / risk.** Medium / medium (exercise names are free text; PR logic on messy names).

## Picks: A and B

A is the only candidate that closes a filed data-loss gap (BUG-17's backgrounding half) and it forces the migration ladder to carry a real step. B exercises the two schema features that have existed since v1 and never run — cascade and replace — under the FK guarantee Stage 1 restored, and it lands the first update/delete path. Both reuse `ActiveScreen`, so the presentation cost is shared; C and D are additive and fix nothing.

---

## Design — Feature A: persisted draft

**Schema diff (v1 → v2).**
```sql
ALTER TABLE workouts ADD COLUMN status TEXT NOT NULL DEFAULT 'done';
-- 'draft' | 'done'. Existing rows default to 'done' — no backfill needed.
```
A draft *is* a workout row, so exercises/sets reuse the existing tables and cascade. No JSON blob, no parallel tables, no codec.
**Migration.** `_onUpgrade`: `if (oldVersion < 2) ALTER TABLE …`. `_createDB` gains the column inline. A v1 user's rows are readable unchanged; `getWorkouts` filters `status = 'done'`.

**Data layer.** `WorkoutLocalDatasource`: `upsertWorkout(model, status:)` (INSERT OR REPLACE; FK ON → children cascade, then reinsert — the replace trap used on purpose), `getWorkouts()` (done only), `getDraft()`, `deleteWorkout(id)`.
**Domain.** `WorkoutRepository` +`saveDraft`, `getDraft`, `deleteWorkout`. Use cases `SaveDraft`, `GetDraft`, `DiscardDraft` — separate classes because each is a distinct *policy*: `SaveDraft` must never bump the streak, `DiscardDraft` is the only sanctioned delete of a non-done row.
**State (sealed by convention, `WorkoutState`):** `WorkoutInitialState` · `WorkoutLoadingState` (draft lookup in flight) · `WorkoutInProgressState{id, startedAt, exercises, editing?}` · `WorkoutCompleteState{workout}` · `WorkoutErrorState{message, exercises}`. Loading is a real state because the Active screen must not render "Add Exercise" before it knows whether a draft exists.
**DI.** New use cases → `registerSingleton` (stateless, one instance is correct). `WorkoutBloc` stays a factory (route-scoped).
**Lifecycle decision.** No `AppLifecycleState` hook. `paused` does not fire on process kill and cannot be awaited on `detached`; write-through on every mutation is the only strategy that survives all three cases. The timer is seeded from `now − startedAt` on resume so it, too, survives.
**Trace.** Tap ✓ on a set → `ExerciseLogCard._submitSet` → `WorkoutBloc.add(SetLogged)` → `_onSetLogged` emits `WorkoutInProgressState` → `await _persistDraft()` → `SaveDraft(workout)` → `WorkoutRepositoryImpl.saveDraft` → `WorkoutLocalDatasourceImpl.upsertWorkout(status:'draft')` → one transaction: `INSERT OR REPLACE workouts`, cascade deletes old children, reinsert exercises/sets. Process dies. Relaunch → Home `initState` → `GetDraft` → banner. Tap Resume → `/active` → `WorkoutStarted` → `_onStarted` emits Loading, `GetDraft` → `WorkoutInProgressState(id: draft.id, startedAt: draft.date, …)` → `_ActiveBody` listener seeds `WorkoutTimerStarted(from: now − startedAt)`.
**Failure modes.** Draft write fails → `addError`, state unchanged, user keeps editing (in-memory is still authoritative); next mutation retries. Two drafts cannot exist (`getDraft` takes newest; finish deletes by id). Finish → `SaveWorkout` upserts same id with `status:'done'` in one statement, so a crash mid-finish leaves either a draft or a done row, never both.
**Tests.** Datasource: draft round-trip, `getWorkouts` excludes drafts, finish flips status, v1→v2 migration on a hand-built v1 file. Bloc: mutation writes draft, start resumes draft, finish deletes draft.

## Design — Feature B: edit and delete

**Schema.** None beyond A.
**Data.** `deleteWorkout(id)` → `DELETE FROM workouts WHERE id = ?` (cascade). `updateWorkout(model)` → same upsert as save with `status:'done'`.
**Domain.** `DeleteWorkout`, `UpdateWorkout` use cases. `UpdateWorkout` is not `SaveWorkout`: the caller of *save* is expected to bump the streak; the caller of *update* must not. Encoding that at the use-case boundary keeps the rule out of the widget.
**State.** `WorkoutInProgressState.editing: Workout?` — when set, mutations skip draft persistence and Finish calls `UpdateWorkout` keeping the original `id` and `date`.
**Events.** `WorkoutEditStarted(Workout)`.
**Routing.** `/active` reads `state.extra as Workout?`; present → `WorkoutEditStarted`, absent → `WorkoutStarted`. History pushes with `extra`.
**DI.** Use cases singletons; no new blocs. History stays `FutureBuilder`-driven and calls `DeleteWorkout` directly then reloads — consistent with its existing read path; a `HistoryBloc` is the next refactor, not this one.
**Trace.** History card long-press → Delete → confirm → `sl<DeleteWorkout>()(id)` → repo → datasource `DELETE` → SQLite cascades exercises/sets → `_reload()` → `FutureBuilder` re-runs → card gone. Edit → `context.push('/active', extra: workout)` → route builder dispatches `WorkoutEditStarted` → `_onEditStarted` emits `InProgress(editing: workout, exercises: workout.exercises, startedAt: workout.date)` → timer seeded from `workout.durationSeconds` → Finish → `UpdateWorkout` → upsert → `WorkoutCompleteState` → `go('/')`.
**Failure modes.** Delete fails → snackbar, list unchanged. Update fails → `WorkoutErrorState` then back to `InProgress` (same recovery path as BUG-26). Editing never writes a draft, so abandoning an edit leaves the original intact.
**Tests.** Datasource: delete cascades, update replaces children without duplicates. Bloc: edit start seeds state; finish-in-edit calls update not save and does not touch the streak.

---

## Design — Feature D: per-exercise progress and PRs (built, round 6)

**User view.** In History, expand a workout and tap an exercise name → a screen with the exercise's personal record (weight × reps, the day it was set, how many training days) and, newest first, the top set of every training day as a bar proportional to the PR. The PR row is badged `PR`; later days that equal it are badged `= PR`.

**Scope cut, stated up front.** D ships **without the live "new PR" badge on save**. The detail screen is a `FutureBuilder` fetched on mount — the same shape as History and Calendar — so it needs no reactive read path. The badge is the only part of D that does, and it is the first thing to add once `HistoryBloc` exists (see `HANDOFF.md` §5). No streams were introduced.

**The three things this feature is for, and how each landed.**

1. *A real aggregate query.* `ProgressLocalDatasourceImpl.topSetPerWorkout(nameKey)` is the first read SQLite computes rather than the app hydrating `Workout`s and reducing in Dart: an inner `GROUP BY workout` for the max weight, an outer join for the most reps at that weight, `WHERE status = 'done'` repeated because the filter is not a constraint. It returns one row per finished workout — `(workoutId, date, reps, weight)` — and nothing else.
2. *A read model that is not an entity.* `domain/read_models/exercise_progress.dart`: `ExerciseProgress { key, displayName, days: [ExerciseTopSet], prIndex }`. Domain owns the shape (so presentation never imports data) and the two rules over it — the civil-day fold and the PR ordering — but it sits under `read_models/`, not `entities/`, and has its own `ProgressRepository`, because it is a derived, read-only projection across many workouts, not an aggregate root. Rationale in `WALKTHROUGH.md` §8b.
3. *The exercise-name key.* `normalizeExerciseName(name) = name.trim().toLowerCase()` in `domain/exercise_name.dart`; stored as `exercises.name_key` (schema v4, indexed) and written only by `upsertWorkout`. Query-time grouping is on the column, not `COLLATE NOCASE`, because Dart's case-fold is Unicode-aware and SQLite's `lower()` is ASCII-only — the v4 backfill therefore runs in Dart too. Display name when variants disagree: the spelling from the **most recent** finished workout. The `WorkoutBloc` now dedupes within a session by the same rule. No rename/merge UI.

**Definitions (each is a test name).**
- *Top set of a workout*: max weight, then max reps at that weight.
- *Top set of a day*: sets are reduced per workout in SQL; the domain folds workouts into civil days with `civilDate` (two sessions on one day keep the stronger). The fold is in Dart, not `substr(date,1,10)`, so the app's DST-safe day rule is the one applied — proven by the DST fold test failing against naive elapsed-hours arithmetic.
- *PR*: lexicographic `(weight, reps)` — a heavier single beats more reps at a lower weight; equal weight → more reps. On an exact tie the **earliest** day keeps the PR, later equal days *match* it.

**Invariants touched.** `status = 'done'` (a draft with a heavier set creates no PR — tested). Kilograms below presentation (the repository returns stored kg; `formatWeight` converts on the screen — tested end to end with lbs). Civil-date arithmetic (no new date math; `civilDate` only — tested across the spring-forward pair with the zone set in-process).

**Surface.** Data: `progress_local_datasource.dart`, `progress_repository_impl.dart`, `name_key` column + index (v4). Domain: `exercise_name.dart`, `read_models/exercise_progress.dart`, `repositories/progress_repository.dart`, `usecases/get_exercise_progress.dart`. Presentation: `screens/exercise_progress_screen.dart`, route `/exercise` (extra = name as typed), `WorkoutSummaryCard.onExerciseTap` wired from History.

**Interaction sweep (all tested on real SQLite).** PR while a draft is open; editing the workout that holds the PR set; deleting it; a draft whose name differs only in case joining the series once finished; a backdated finished draft landing mid-history (tie keeps the earlier PR, heavier takes it).

**Risk accepted.** Names are still free text; "BP" and "Bench Press" are two exercises and will stay so until someone wants a merge feature.
