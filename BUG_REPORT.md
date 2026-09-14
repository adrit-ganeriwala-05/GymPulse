# GymPulse — Phase 1 Bug Audit

**Date:** 2026-09-14
**Commit audited:** `7518cbc` (Initial commit)
**Analyzer baseline:** `flutter analyze` → **No issues found!** (clean before any changes)
**Toolchain:** Flutter 3.41.6 · Dart SDK ^3.11.4 · bloc 8.1.4 · flutter_bloc 8.1.6 · go_router **13.2.5** · sqflite 2.4.2+1 · get_it 7.7.0 · google_fonts 6.3.3

> **No fixes have been applied.** This report is for approval and priority ordering only.

---

## 0. Document-integrity note (read this first)

**`project_context.md` does not exist in this repository.** The only Markdown file present is `README.md`.
I searched the working directory, the `gympulse/` project root, `.claude/`, and `.github/`.

```
$ find . -iname "*context*" -not -path "*/build/*" -not -path "*/.git/*"
(no results)
```

So the "map, not truth" instruction had nothing to verify against. Everything below is derived
directly from source. I have flagged places where the **audit checklist in your brief** makes a claim
that the code contradicts — those are the equivalent signal, marked **[CHECKLIST WRONG]**.

Three checklist items were wrong, and one was right for the wrong reason. Details in §3.

---

## 1. Summary table

| ID | Sev | Area | One-line |
|----|-----|------|----------|
| [BUG-01](#bug-01) | **Critical** | Data | Weight unit is a global display label; toggling kg↔lbs silently relabels all history and sums mixed-unit volume |
| [BUG-02](#bug-02) | **Critical** | Data | `double.tryParse` accepts `NaN`/`Infinity`; NaN violates `NOT NULL` and makes the whole workout permanently unsaveable |
| [BUG-03](#bug-03) | **Critical** | Streak | DST spring-forward makes `inDays` return 0 for consecutive days — *day-truncation does not save you* |
| [BUG-04](#bug-04) | **Critical** | Data | Schema `version: 1` with no `onUpgrade`; any future bump throws and bricks every existing install |
| [BUG-05](#bug-05) | High | Data | `PRAGMA foreign_keys = ON` inside `onCreate` is a **silent no-op** (runs in a transaction) |
| [BUG-06](#bug-06) | High | Data | Workout date stamped at *finish*, not start — midnight crossing misfiles the workout |
| [BUG-07](#bug-07) | High | Streak | `markRestDay()` burns a rest token on a day that already has a workout |
| [BUG-08](#bug-08) | High | Async | `RestDayMarked` is not idempotent; bloc's default transformer is **concurrent**, so read-modify-write races |
| [BUG-09](#bug-09) | High | Streak | "Best Streak" and "current streak" use different definitions and disagree on screen |
| [BUG-10](#bug-10) | High | Streak | `markRestDay()` writes `last_workout_date`, conflating rest with training; callable before any streak exists |
| [BUG-11](#bug-11) | High | Errors | `snapshot.data ?? []` renders a DB failure identically to "no workouts yet"; zero logging app-wide |
| [BUG-12](#bug-12) | High | Data | **[NOT ON THE LIST]** Race in `WorkoutDatabase.database` getter can open the DB twice |
| [BUG-13](#bug-13) | Medium | Routing | `key: UniqueKey()` remounts + refetches `/history` on every Router rebuild |
| [BUG-14](#bug-14) | Medium | Lifecycle | One-shot load lives in `didChangeDependencies` |
| [BUG-15](#bug-15) | Medium | Input | **[NOT ON THE LIST]** Onboarding name validation is bypassable by swiping the `PageView` |
| [BUG-16](#bug-16) | Medium | Async | `setState` after `await` with no `mounted` guard in `_handleNext` |
| [BUG-17](#bug-17) | Medium | Routing | System-back out of `/active` silently discards an in-progress workout |
| [BUG-18](#bug-18) | Medium | Streak | Progress bar `thisWeek / 5` contradicts the 2-rest-day (5-day) week, and uses a rolling 168h window |
| [BUG-19](#bug-19) | Medium | Streak | The magic number `2` is duplicated in three places |
| [BUG-20](#bug-20) | Medium | Platform | Web/Windows/Linux are configured but sqflite has no implementation → runtime failure |
| [BUG-21](#bug-21) | Medium | Platform | google_fonts fetches over HTTP; breaks the offline-first claim on cold first launch |
| [BUG-22](#bug-22) | Medium | Streak | `_initWeekIfNeeded()` rolling window never aligns to a real week; allowance resets mid-week |
| [BUG-23](#bug-23) | Medium | Input | Zero/negative reps and weights reach the database unchallenged |
| [BUG-24](#bug-24) | Low | Dead code | 4 orphaned widgets, unused JSON codec, unused bloc event/state, unused dependency, phantom legend, 3 duplicate formatters |
| [BUG-25](#bug-25) | Low | UX | Rest-timer custom-duration field has no upper bound and no commit affordance |

**Counts:** 4 Critical · 8 High · 11 Medium · 2 Low = **25 findings**, 2 of which the checklist did not anticipate.

---

## 2. Findings

### <a name="bug-01"></a>BUG-01 — Weight unit is display-only; history is relabelled, not converted

| Field | Content |
|---|---|
| **Severity** | **Critical** (silent data corruption — every historical number becomes wrong) |
| **Location** | `lib/domain/entities/exercise.dart:1-6` · `lib/data/repositories/settings_repository_impl.dart:8` · `lib/data/datasources/workout_database.dart:52-62` · consumers: `workout_summary_card.dart:36-38,74,105,116`, `calendar_screen.dart:320-321,341,365`, `exercise_log_card.dart:80` |

**Symptom**
I log a 100 kg bench press. I toggle the unit chip on the Active screen to LBS. I open History: the same
set now reads **"100 lbs"**. The number did not change — only the suffix did. My 100 kg lift has been
silently restated as a 45 kg lift. Total volume on the calendar detail sheet and the summary card
change units too, without changing value. Toggle back and it reads 100 kg again. The database never moved.

**Root cause**
`ExerciseSet.weight` is a bare `double` with no unit attached:

```dart
class ExerciseSet {
  final int reps;
  final double weight;   // ← unit-less. 100 of *what*?
}
```

The unit lives in exactly one place — a single global `SharedPreferences` string under key
`weight_unit` (`settings_repository_impl.dart:8`), default `'kg'`. Every display site reads *that one
global* and concatenates it as a suffix. There is no conversion arithmetic anywhere in the codebase;
I grepped for it — no `2.20462`, no `0.453592`, no conversion function exists.

So the unit is a **property of the app's current UI preference**, not a property of the datum. That is
the defect: a measurement without its unit is not a measurement. Worse, `_totalVolume`
(`workout_summary_card.dart:36-38`) folds `reps * weight` across *all* sets of *all* exercises in a
workout. If the setting were ever per-set, this sum would be adding kg to lbs. Today it is
"consistent" only because the unit is global — which is precisely what makes the relabelling bug possible.

**Repro**
1. Fresh install, unit defaults to `kg`. Start a workout, add "Bench", log `10 reps × 100`.
2. Finish. History shows `10 reps × 100.0 kg`, volume `1000 kg`.
3. Start another workout. Tap the unit chip → it reads `LBS`.
4. Re-open History. The *same historical set* now reads `10 reps × 100.0 lbs`, volume `1000 lbs`.

**Proposed fix — (b) store canonical kg, convert at the display boundary**

You asked me to argue between three options. Taking them in turn:

- **(a) Store a unit per set.** Most faithful to reality, and correct for a user who genuinely logs
  some lifts in lbs (US plates) and others in kg. But it makes *every* aggregate a conversion site:
  `_totalVolume` can no longer be a plain `fold`, it must normalise each set first. It pushes unit
  logic into the domain entity and into every widget that sums. It also requires a schema migration
  *and* a backfill guess for existing rows (what unit were they?). Highest correctness, highest cost,
  and it solves a problem this app's UI does not actually present — there is one global toggle, not a
  per-set picker.

- **(c) Store a single app-wide unit and convert the whole table on toggle.** Tempting because it
  keeps reads dumb. But it means an `UPDATE sets SET weight = weight * 2.20462` across the entire
  table every time someone taps a chip. That is a destructive, lossy (floating-point drift compounds
  on repeated toggles), non-atomic-with-the-preference write. If the app is killed mid-update, half
  the table is in kg and half in lbs with no marker saying which. It converts a display concern into
  a data-migration event. **Reject.**

- **(b) Store canonical kg; convert only when rendering and when parsing input.** ✅
  The database has exactly one meaning: `weight` is kilograms, always. The toggle becomes a pure view
  concern. Aggregates stay trivial `fold`s because everything in the store shares a unit. Input is
  converted once, at the point of parse, before it enters the domain. Toggling is free, instant,
  lossless, and idempotent. This is the standard "canonical storage, presentation-boundary conversion"
  pattern — the same reason you store UTC and render local.

  Mechanically it needs: a `UnitConverter` in the presentation layer (or a domain value object if you
  want `Weight` to be a real type), conversion on the way *in* at `exercise_log_card.dart:38`, and
  conversion on the way *out* at each of the five display sites. **Domain stays Flutter-free and
  package-free**, satisfying the dependency rule.

  One honest caveat: (b) cannot represent "this user logged this specific lift in lbs on a US
  plate-loaded bar". If you later want that fidelity, (b) is still the right base — you add a
  `display_unit` column as *metadata*, and canonical kg remains the source of truth. (b) does not
  block (a); (c) actively fights it.

**Behaviour change (when fixed):** yes, and it needs a decision from you. Existing rows have no
recorded unit. I propose treating all existing data as **kg** (the app's default, and almost certainly
what was entered), and saying so in the migration. Any other choice is a guess that silently rescales
real user data.

**Blast radius**
`ExerciseSet` entity · `sets` table schema/migration · `ExerciseSetModel` · the `SetLogged` event
payload · `_submitSet` parse path · all 5 display sites · `_totalVolume` in 2 files · the settings
toggle handler. This is the single most invasive fix in the report and should be sequenced carefully
against BUG-04 (migration path) — they share a migration.

---

### <a name="bug-02"></a>BUG-02 — `NaN`/`Infinity` pass validation; NaN makes the entire workout permanently unsaveable

| Field | Content |
|---|---|
| **Severity** | **Critical** (total loss of an in-progress workout, unrecoverable without discarding) |
| **Location** | `lib/presentation/widgets/exercise_log_card.dart:36-44` · `lib/data/datasources/workout_database.dart:56` · `lib/presentation/blocs/workout/workout_bloc.dart:80-89` |

**Symptom**
The user types `NaN` into the weight field (or `Infinity`, or `1e309`). The set is accepted and appears
in the exercise card. They finish the workout and tap **Save & Finish**. A snackbar says
*"Failed to save workout"*. It says that **every single time they retry**. The workout — possibly an
hour of logged training — can never be saved. Their only escape is to abandon it.

**Root cause**
The validation is a null-check and nothing more:

```dart
void _submitSet() {
  final reps = int.tryParse(_repsCtrl.text.trim());
  final weight = double.tryParse(_weightCtrl.text.trim());
  if (reps == null || weight == null) return;   // ← the ONLY guard
  widget.onAddSet(reps, weight);
```

`double.tryParse` is not a numeric-sanity check. Verified against the actual Dart SDK:

```
double.tryParse(Infinity  ) = Infinity
double.tryParse(-Infinity ) = -Infinity
double.tryParse(NaN       ) = NaN
double.tryParse(1e309     ) = Infinity     ← ordinary-looking input, overflows to Infinity
double.tryParse(-5        ) = -5.0
```

None of these are `null`, so all pass. The value flows `SetLogged` → `WorkoutInProgressState` →
`WorkoutModel` → `txn.insert('sets', {'weight': NaN})`.

Now the SQLite half, which is the part that turns a display glitch into data loss. **SQLite converts
NaN to NULL on storage** — and the column is declared `weight REAL NOT NULL`
(`workout_database.dart:56`). Verified:

```
$ sqlite3 ... "CREATE TABLE sets (id TEXT PRIMARY KEY, weight REAL NOT NULL);
               INSERT INTO sets VALUES ('b', 9e999 - 9e999);"
Error: stepping, NOT NULL constraint failed: sets.weight (19)
```

The insert throws inside `db.transaction`. sqflite rolls the transaction back (so the DB stays clean —
see BUG-E2 verdict in §3), the exception propagates to `_onFinished`, and the `try/catch` at
`workout_bloc.dart:80` converts it to `WorkoutErrorState`. The catch is *load-bearing for the crash*
but does nothing for the user: the poisoned set is still sitting in `current.exercises`, which
`WorkoutErrorState` faithfully carries forward (`workout_bloc.dart:86-88`). Retrying re-submits the
same NaN. **The failure is deterministic and permanent.**

`Infinity` is the quieter sibling: it stores fine as REAL `Inf`, then every aggregate reads
`Infinity`, and `toStringAsFixed(0)` renders the literal string `"Infinity"` — verified — so the
history card reads `📦 Infinity kg` forever.

**Repro**
1. Start workout → Add Exercise "Bench" → Log Set.
2. Reps `10`, weight `NaN` (three keystrokes, no special characters — this is reachable on a plain
   numeric keyboard on desktop/web, and via paste or a hardware keyboard on mobile).
3. Tap ✓. The set is accepted and rendered.
4. Finish Workout → Save & Finish → *"Failed to save workout"*. Retry forever.

**Proposed fix**
Validate the *domain meaning*, not the parse result, at the presentation boundary:

```dart
if (reps == null || reps <= 0 || reps > 1000) return;           // + user-visible error
if (weight == null || !weight.isFinite || weight < 0 || weight > 1000) return;
```

`weight.isFinite` is the precise predicate — it is false for both NaN and ±Infinity, which is exactly
the class of values SQLite cannot round-trip. Pair it with `errorText` on the fields so the rejection
is *visible*; today `_submitSet` returns silently, which is its own small bug (the user taps ✓ and
nothing happens, with no explanation).

*Why not fix it in the datasource?* You could reject there, but the user has by then already logged
the set and moved on — the error surfaces an hour later at save time. Validation belongs at the
point of entry, where the user still has context to correct it. A defensive check in the model layer
is reasonable belt-and-braces, but it is not the fix.

*Why not make the column nullable?* Because a set with no weight is not a real set. The `NOT NULL`
constraint is correct and is doing its job — it caught bad data. The bug is upstream.

**Behaviour change:** yes. Inputs that are currently silently accepted (`0` reps, negative weight,
`NaN`) will be rejected with a visible message. This is the point.

**Blast radius**
`_submitSet` only, plus the `reps`/`weight` `TextField`s for error display. Low-risk, high-value —
I recommend this as the **first fix**, ahead of BUG-01, because it is small, self-contained, and stops
active data loss.

---

### <a name="bug-03"></a>BUG-03 — DST spring-forward breaks the streak; day-truncation is *not* sufficient

| Field | Content |
|---|---|
| **Severity** | **Critical** (silently destroys a streak the user has earned — the app's core promise) |
| **Location** | `lib/data/datasources/streak_local_datasource.dart:45,103` · `lib/presentation/screens/home_screen.dart:85,87` |

**Symptom**
A user in any DST-observing timezone works out on the day before the clocks spring forward, and again
the next day. Their streak **does not increment**. On the "Best Streak" stat on Home, the streak
visibly *resets to 1*. Once a year, on a date the user cannot predict, consecutive training silently
fails to count.

**Root cause**
This is the item the checklist got half-right, and the half it missed is the important half.

The checklist says: *"is every comparison done on day-truncated `DateTime`s? `difference(...).inDays`
truncates toward zero and will report 0 for a 23-hour gap that crosses midnight."*

The first clause checks out — `updateStreak` *does* truncate correctly:

```dart
final now = DateTime.now();
final today = DateTime(now.year, now.month, now.day);   // ← midnight, local
...
final daysDiff = today.difference(lastDate).inDays;
```

Both operands are local midnights. So one would conclude the truncation defends against the 23-hour
problem. **It does not**, and this is the mechanically interesting part:

`DateTime.difference` returns a `Duration` of **absolute elapsed time**. `Duration.inDays` is integer
division by 24 hours. On the spring-forward boundary, two consecutive *local midnights* are only
**23 real hours apart**, because one hour of wall-clock time does not exist. `23 ~/ 24 == 0`.

Verified on this machine (US timezone, so the transition reproduces directly):

```
DST fwd (Mar 9→10 2025): b-a hours=23  inDays=0     ← consecutive days read as "same day"
DST back (Nov 2→3 2025): d-c hours=25  inDays=1     ← survives by luck
23:30 → 00:30 (no DST):                inDays=0     ← the checklist's case, on raw timestamps
```

Trace the consequence through `updateStreak` (lines 45-53):
- `daysDiff == 0` → the `if (daysDiff == 0) return;` branch fires → **the streak does not increment,
  and `last_workout_date` is not even updated**. The user trained; the app recorded nothing.
- The next day, `daysDiff` is computed from the *stale* `last_workout_date` → `2` → falls to the
  `else` branch → `streak = 1`. **The streak is reset.**

Fall-back (25h → `inDays == 1`) happens to land on the correct branch, so only one of the two annual
transitions bites. That is luck, not design.

The same defect is in the Home screen's client-side "Best Streak" recomputation
(`home_screen.dart:85,87`), which uses the identical `day.difference(last).inDays == 1` idiom on
truncated dates. And in `_initWeekIfNeeded` (`line 103`), where `>= 7` can be reached a day late.

A related, more common variant: a user who flies from London to Los Angeles. `DateTime.now()` follows
the device's new timezone. Two local midnights spanning the flight can be 32 hours apart
(`inDays == 1`, fine) or, flying the other way, 16 hours apart (`inDays == 0` — a consecutive day
silently swallowed).

**Repro**
1. Set the device timezone to `America/New_York`.
2. Set the date to 2025-03-08. Complete a workout. Streak = 1.
3. Advance the device to 2025-03-09 (spring-forward day). Complete a workout.
4. **Expected** streak 2. **Actual** streak 1, and `last_workout_date` still reads 2025-03-08.
5. Advance to 2025-03-10, work out → streak resets to 1 instead of reaching 3.

**Proposed fix**
Stop measuring calendar distance with a physical-time `Duration`. Compare **civil dates** directly:

```dart
int _civilDaysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;
```

Projecting both dates onto the **UTC** timeline before subtracting makes every day exactly 24 hours
by construction, because UTC has no DST. The `DateTime.utc(...)` values are never displayed and never
stored — they are a pure arithmetic device for computing a calendar delta. This is the standard
"civil date arithmetic" technique and is why `package:time`/`Jiffy` exist; we do not need the
dependency for one three-line helper (see §5, dependency policy).

*Why not just compare `y/m/d` field-by-field?* That answers "same day?" but not "how many days
apart?", and the gap>1 branch needs the magnitude.

*Why not store a day-ordinal `int` instead of a date string?* Genuinely attractive — it makes the bug
unrepresentable. But it is a storage-format change on top of BUG-04's migration, and it makes the
persisted value opaque when debugging. I'd rather fix the arithmetic and keep the readable date. Open
to argument.

*Why not UTC-everything?* Because "did I work out today?" is a question about the user's *local*
calendar. A 7pm PST workout is Tuesday to the user and Wednesday in UTC. Storing local-midnight and
comparing via a UTC projection keeps the semantics local and the arithmetic sound.

**Behaviour change:** yes, and it is a correction — streaks that would previously have broken on the
DST boundary now continue. No existing stored data changes meaning.

**Blast radius**
`updateStreak`, `markRestDay`, `_initWeekIfNeeded` (all three call sites in the datasource), plus the
duplicate logic in `home_screen.dart:85-87`. This is the finding that most needs the injectable-clock
refactor from your Phase 2 test plan — it is untestable today because `DateTime.now()` is called
inside the datasource.

---

### <a name="bug-04"></a>BUG-04 — Schema `version: 1` with no `onUpgrade`: any future bump bricks existing installs

| Field | Content |
|---|---|
| **Severity** | **Critical** (data loss / hard crash on launch for every existing user, the moment the schema changes) |
| **Location** | `lib/data/datasources/workout_database.dart:19-26` |

**Symptom**
Today: nothing. This is a **latent** critical. The moment anyone ships a schema change — which
BUG-01's per-set unit column and *three of the four Phase-3 features* all require — every user who
already has `gympulse.db` on disk gets an unhandled exception on launch, and the app is unusable
until they clear app data (losing all workouts).

**Root cause**
```dart
final db = await openDatabase(
  path,
  version: 1,
  onCreate: _createDB,       // ← no onUpgrade, no onDowngrade, no onConfigure
);
```

`openDatabase` dispatches on the delta between the on-disk `PRAGMA user_version` and the requested
`version`:
- on-disk `0` (new file) → runs `onCreate`. This is the only path exercised today, which is why
  nothing is broken yet.
- on-disk `< version` → runs `onUpgrade`. **It is null here.** sqflite throws
  `ArgumentError("onUpgrade must be specified")` — it does not silently no-op and it does not fall
  back to `onCreate`.
- on-disk `> version` (a user who downgrades the app) → runs `onDowngrade`, also null. sqflite's
  default for this case is `onDatabaseDowngradeDelete` **only if you pass it explicitly**; unset, it
  throws too.

So the schema is effectively frozen. The tables already anticipate growth — `ON DELETE CASCADE` on
both child tables exists for an edit/delete feature that cannot be built without a migration — which
makes the missing `onUpgrade` a structural gap, not a style nit.

**Repro**
1. Run the app once on a clean device; log a workout. `user_version` on disk is now `1`.
2. Change `version: 1` → `version: 2` in `_initDB` (simulating any schema change).
3. Relaunch. The first DB access throws; `GetWorkouts` fails; per BUG-11 the Home screen renders the
   empty state, so the user is told **"No workouts yet. Start your first!"** — their data appears to
   have vanished.

**Proposed fix**
Introduce the migration scaffold *now*, while the only version is 1 and the cost is zero:

```dart
final db = await openDatabase(
  path,
  version: 1,
  onConfigure: _onConfigure,   // ← also fixes BUG-05
  onCreate: _createDB,
  onUpgrade: _onUpgrade,
);

Future<void> _onUpgrade(Database db, int oldV, int newV) async {
  // Sequential, forward-only, each step idempotent w.r.t. its own version gate.
  if (oldV < 2) { /* v2 DDL */ }
  if (oldV < 3) { /* v3 DDL */ }
}
```

The `if (oldV < N)` ladder (rather than a `switch`) is what makes a user on v1 jumping straight to v4
apply every intermediate step in order. `_createDB` must then be kept in lockstep so a *fresh* install
lands on the same shape a *migrated* install does — the classic divergence bug. The alternative
(`onCreate` creates v1, then immediately calls `_onUpgrade(db, 1, newV)`) guarantees they cannot
diverge and is what I'd recommend when we first actually bump the version.

*Why not `onDatabaseDowngradeDelete` for downgrades?* It wipes user data. Acceptable as a last resort
for a downgrade (a rare, user-initiated event), and far better than an unlaunchable app — I'd wire it
with a comment saying exactly that, but I want your call before I make data deletion a default.

**Behaviour change:** none today (no version bump in this fix). It is pure groundwork.

**Blast radius**
`_initDB` signature and `workout_database.dart` only. But it **gates BUG-01** and Phase-3 features
2, 3 and 4 — nothing that touches the schema can land before it. Recommend fixing it early despite
having no user-visible symptom.

---

### <a name="bug-05"></a>BUG-05 — `PRAGMA foreign_keys = ON` inside `onCreate` is a silent no-op

| Field | Content |
|---|---|
| **Severity** | High (FK enforcement is load-bearing for `INSERT OR REPLACE`; currently correct only by accident) |
| **Location** | `lib/data/datasources/workout_database.dart:24` and `:29` |

**Symptom**
None today. But the guarantee the schema relies on is held up by the *less obvious* of two lines,
while the obvious one does nothing — so any future refactor that "tidies up" the duplicate is likely
to remove the one that works.

**Root cause — and a correction to the checklist**

**[CHECKLIST WRONG]** The brief says: *"Verify it is set in `onConfigure`, not just in `onCreate`/the
DDL string. If it's only in `onCreate`, FK enforcement is silently off on every subsequent app
launch."* The premise is right, the diagnosis is not — because the pragma is in **two** places:

```dart
Future<Database> _initDB(String filePath) async {
  final db = await openDatabase(path, version: 1, onCreate: _createDB);
  await db.execute('PRAGMA foreign_keys = ON');   // line 24 — OUTSIDE. This one works.
  return db;
}

Future<void> _createDB(Database db, int version) async {
  await db.execute('PRAGMA foreign_keys = ON');   // line 29 — INSIDE onCreate. No-op.
```

Line 24 runs after `openDatabase` returns, on the live connection, outside any transaction — it is
effective, and it runs on **every** launch. So FK enforcement is **currently ON**, and the checklist's
predicted failure does not occur.

Line 29 is the dead one, for a reason worth knowing: **sqflite wraps `onCreate`/`onUpgrade` in a
transaction**, and `PRAGMA foreign_keys` is documented as *"a no-op within a transaction"*. Verified
directly against SQLite:

```
inside txn,  fk=0      ← PRAGMA foreign_keys = ON issued inside BEGIN...COMMIT
after commit, fk=0     ← and it does not take effect on commit, either
outside txn, fk=1      ← same statement, no transaction
```

It fails **silently** — no error, no warning. That is the trap.

Why this matters beyond tidiness — it is exactly what makes BUG-06's `ConflictAlgorithm.replace`
safe. Verified both ways:

```
FK ON : children before replace=1 → children after replace=0   (cascade fired)
FK OFF: children after replace=1                                (children survive → duplicates)
```

So the correctness of the save path depends on line 24 and *only* line 24.

**Repro**
Cannot be reproduced as a user-visible failure today — that is the point. To observe the no-op:
add `print(await db.rawQuery('PRAGMA foreign_keys'))` as the last statement of `_createDB` on a fresh
install; it reports `0`.

**Proposed fix**
Move it to `onConfigure`, delete both current copies:

```dart
Future<void> _onConfigure(Database db) async =>
    db.execute('PRAGMA foreign_keys = ON');
```

`onConfigure` is the callback sqflite invokes **before** any create/upgrade logic and **outside** the
migration transaction, on every open. It is the only hook with both properties, which is why it is the
documented home for this pragma. It also correctly enables FKs *during* a future `onUpgrade` — which
line 24 does not, since it runs after migrations have already finished.

*Why not leave line 24 and just delete line 29?* It works, but it leaves FKs off during migrations —
precisely when cascade behaviour matters most (BUG-04). `onConfigure` is strictly better and is one line.

**Behaviour change:** none today. It changes FK state *during future migrations* from off to on,
which is the desired semantic.

**Blast radius** `workout_database.dart` only.

---

### <a name="bug-06"></a>BUG-06 — Workout date stamped at finish time, not start

| Field | Content |
|---|---|
| **Severity** | High (wrong data shown; corrupts streak, calendar and history grouping) |
| **Location** | `lib/presentation/blocs/workout/workout_bloc.dart:74` |

**Symptom**
A user starts a workout at 23:30 and finishes at 00:15. The session is filed under **tomorrow**.
The calendar puts a dot on the wrong day; History sorts it into the wrong group; and the streak
credits the wrong day — so a Monday-night session can leave Monday looking like a missed day *and*
double-count Tuesday.

**Root cause**
```dart
final workout = Workout(
  id: const Uuid().v4(),
  date: DateTime.now(),          // ← evaluated in _onFinished, i.e. at save time
  durationSeconds: event.durationSeconds,
```

`_onFinished` runs when the user taps **Save & Finish**. Nothing captures the start instant. The
`WorkoutTimerBloc` knows the *elapsed* seconds but not the *origin* — `WorkoutTimerRunningState`
carries only an `int seconds` counter (`workout_timer_state.dart:14-21`), and
`WorkoutInProgressState` carries only `List<Exercise>` (`workout_state.dart:17-24`). The start time
is genuinely not recorded anywhere in the app.

Note the compounding interaction with BUG-03: `updateStreak()` is called from `_onFinished`
immediately after, and it independently calls `DateTime.now()` again — so the workout row and the
streak bookkeeping are stamped from two *separate* clock reads. They will normally agree, but they
are not guaranteed to, and neither is anchored to when training actually began.

**Repro**
1. At 23:50, start a workout, log a set.
2. At 00:10 the next day, tap Save & Finish.
3. Calendar: the dot lands on the new day, not the day the session began.
4. Streak: the previous day is treated as having no workout.

**Proposed fix**
Capture the start instant when the session begins and carry it in the state:

- `WorkoutInProgressState` gains `final DateTime startedAt`.
- `_onStarted` sets it: `emit(WorkoutInProgressState(exercises: [], startedAt: _clock.now()))`.
- `_onFinished` uses `current.startedAt` instead of a fresh `DateTime.now()`.

This also makes the workout's date **injectable for tests** via the same clock seam BUG-03 needs, and
removes the second, independent `now()` read.

*Alternative — keep finish-time but "snap back" if the session crossed midnight.* Heuristic,
surprising, and wrong for a genuinely post-midnight workout (a 01:00 session is legitimately today).
Reject.

*Alternative — store both start and end.* Strictly more information, and honestly defensible
(`duration` becomes derivable rather than separately tracked). But it needs a schema column, so it
belongs with the BUG-04 migration rather than in a minimal fix. Worth raising as a Phase-3 design question.

**Behaviour change:** yes — a midnight-crossing workout will now be filed under its start day.
Existing rows are unaffected (they keep their recorded finish timestamps).

**Blast radius**
`WorkoutInProgressState` shape (adds a required field → all construction sites), `_onStarted`,
`_onFinished`, and `WorkoutErrorState` (which reconstructs from `current.exercises` and must preserve
`startedAt`). Contained within `workout_bloc.dart` + `workout_state.dart`.

---

### <a name="bug-07"></a>BUG-07 — A rest day can be burned on a day that already has a workout

| Field | Content |
|---|---|
| **Severity** | High (user loses a scarce resource for nothing, with no feedback) |
| **Location** | `lib/data/datasources/streak_local_datasource.dart:60-89` · `lib/presentation/screens/home_screen.dart:204-233` |

**Symptom**
The user trains on Monday. Back on Home, the **"Mark Rest Day (2 left this week)"** button is still
displayed. They tap it — perhaps thinking it logs a *future* rest day, perhaps by accident. The
counter drops to 1. They have spent one of their two weekly rest days on a day they *already trained*,
gaining nothing. There is no confirmation and no way to undo.

**Root cause**
`markRestDay` has two guards, and neither covers this case:

```dart
// Bug 4: validate today is within the current tracked week
if (today.isBefore(weekStart) || today.isAfter(weekEnd)) return;

// Bug 5: prevent marking same day twice
final lastRestStr = prefs.getString(_lastRestDayKey);
if (lastRestStr != null) { ...same-day check on _lastRestDayKey... return; }

final restDays = prefs.getInt(_restDaysRemainingKey) ?? 2;
if (restDays > 0) { ...decrement... }
```

The second guard compares today against `_lastRestDayKey` — *"have I already rested today?"*. It never
compares against `_lastWorkoutDateKey` — *"did I already train today?"*. Those are different questions,
and only the first is asked.

(The `// Bug 4` / `// Bug 5` comments indicate a previous pass fixed adjacent issues and stopped here.)

The UI compounds it: the button's only render condition is `if (restDays > 0)`
(`home_screen.dart:204`). It has no knowledge of whether today already has a workout — the Home
screen *has* that information in the `workouts` list from its `FutureBuilder`, but never consults it
for this decision.

**Repro**
1. Complete a workout today. Streak = 1, rest days = 2.
2. Return to Home. "Mark Rest Day (2 left this week)" is visible.
3. Tap it. Counter → 1. Streak unchanged. Nothing else happens.

**Proposed fix**
Guard in the datasource (authoritative) **and** in the UI (discoverable):

```dart
final lastWorkoutStr = prefs.getString(_lastWorkoutDateKey);
if (lastWorkoutStr != null && _isSameCivilDay(DateTime.parse(lastWorkoutStr), today)) return;
```

…with the caveat that this guard is only sound **after BUG-10 is fixed**, because today
`_lastWorkoutDateKey` is written by `markRestDay` itself, so it does not currently distinguish
"trained today" from "rested today". BUG-07 and BUG-10 must be fixed together or the guard is
meaningless. That coupling is the real lesson here: one key is being used for two different facts.

UI side: hide (or disable with an explanatory label) the button when today already has a workout.

*Why not only fix the UI?* Because the datasource is the invariant-holder; a hidden button is not an
enforced rule, and the rest-day allowance is exactly the kind of scarce resource that needs its
invariant in one authoritative place.

**Behaviour change:** yes — tapping Mark Rest Day on a day you already trained becomes a no-op
(preferably an invisible button). Call out in release notes.

**Blast radius** `markRestDay`, Home's button visibility condition. Coupled to BUG-10.

---

### <a name="bug-08"></a>BUG-08 — `RestDayMarked` is not idempotent under rapid dispatch (bloc's default transformer is concurrent)

| Field | Content |
|---|---|
| **Severity** | High (lost update on a persisted counter) |
| **Location** | `lib/presentation/blocs/streak/streak_bloc.dart:33-40` · `lib/data/datasources/streak_local_datasource.dart:60-89` · `lib/presentation/screens/home_screen.dart:206-209` |

**Symptom**
Double-tapping "Mark Rest Day" decrements the counter **once instead of twice** — or, with different
timing, writes an inconsistent `last_rest_day_date`. The user's rest allowance silently disagrees with
the days they actually marked.

**Root cause**
Two mechanisms compose badly.

**(1) bloc processes events concurrently by default.** Verified in the installed package source, not
from memory — `bloc-8.1.4/lib/src/bloc.dart:62`:

```dart
static EventTransformer<dynamic> transformer = (events, mapper) { ... };
```
with the doc comments at lines 33, 52 and 173 all stating *"By default events are processed
concurrently."* No `transformer:` argument is supplied to `on<RestDayMarked>` in `StreakBloc`, so two
`RestDayMarked` events dispatched in the same frame run their handlers **interleaved**, not serialised.

**(2) `markRestDay` is a read-modify-write split across `await` boundaries.** Every `prefs` call is
awaited, so the handler yields the event loop repeatedly *between* reading the guard value and
writing the decrement:

```dart
final lastRestStr = prefs.getString(_lastRestDayKey);   // read guard
if (lastRestStr != null) { ... return; }                // ← window opens here
final restDays = prefs.getInt(_restDaysRemainingKey) ?? 2;
if (restDays > 0) {
  await prefs.setInt(_restDaysRemainingKey, restDays - 1);   // write
  await prefs.setString(_lastRestDayKey, ...);               // guard only set HERE
```

The guard (`_lastRestDayKey`) is not written until *after* the decrement. So handler B can read
`lastRestStr == null` and `restDays == 2` before handler A has written either. Both compute `2 - 1`
and both write `1`. **Classic lost update**: two taps, one decrement.

The guard is therefore not a lock — it only protects against *sequential* repeats (a tap today after
a tap today), which is the case the `// Bug 5` comment was written for. It does nothing for
concurrent ones.

**Repro**
Double-tap "Mark Rest Day" quickly (or dispatch `RestDayMarked()` twice in a row in a test). Observe
`rest_days_remaining` drop from 2 to 1 rather than to 0. Timing-dependent — on a fast device the
handlers may serialise naturally, which is what makes this the kind of bug that only shows up on a
user's slower phone.

**Proposed fix**
Two changes, both cheap:

1. **Serialise the event.** Give the handler a sequential transformer so a second
   `RestDayMarked` cannot begin until the first completes:
   `on<RestDayMarked>(_onRestDayMarked, transformer: sequential())`.
   This requires `package:bloc_concurrency` — an official `bloc` package. Per your dependency rule:
   the alternative is hand-rolling a queue or a `bool _busy` latch in the bloc, which is (a) the same
   thing with more bugs and (b) state that has to be reset on every error path. `bloc_concurrency` is
   maintained by the bloc authors, is ~100 lines, and exists precisely for this. I think it earns its
   weight — **but it is a new dependency, so I am flagging it for your approval rather than assuming it.**
   If you'd rather not add it, `droppable()` semantics can be approximated by an `isClosed`-style
   guard flag; say the word and I'll do it without the package.

2. **Close the read-modify-write window** by writing the guard key *first*, or better, by making the
   datasource method check-and-set in one logical step. Even with `sequential()`, leaving the window
   open means any *other* future caller re-introduces the race.

Prefer doing both: (1) fixes this call site, (2) fixes the class of bug.

**Behaviour change:** yes — a double-tap now reliably consumes exactly one rest day (the second is
correctly rejected by the same-day guard).

**Blast radius** `StreakBloc` registration, `markRestDay`. Also worth auditing `StreakUpdated` for the
same pattern — it has the identical read-then-write shape.

---

### <a name="bug-09"></a>BUG-09 — "Best Streak" and "current streak" use incompatible definitions

| Field | Content |
|---|---|
| **Severity** | High (two contradictory numbers about the same concept, side by side on one screen) |
| **Location** | `lib/presentation/screens/home_screen.dart:79-92` (client-side) vs `lib/data/datasources/streak_local_datasource.dart:31-57` (persisted) |

**Symptom**
Home shows a 🔥 **current streak** of 5 and, two cards below, a **Best Streak** of 3. Best is smaller
than current, which is logically impossible for any coherent definition of "best". The user cannot
tell which number to believe.

**Root cause**
They are computed by two independent algorithms that disagree about what a streak *is*.

**Persisted `currentStreak`** (`StreakLocalDatasourceImpl`) counts **days on which the streak was
kept alive**, and a rest day *preserves* it. `markRestDay` writes `_lastWorkoutDateKey = today`
(line 87), so the next workout sees `daysDiff == 1` and increments. Rest days bridge gaps.

**Client-side `bestStreak`** (`home_screen.dart:79-92`) recomputes from the workout list alone:

```dart
for (final w in sorted) {
  final day = DateTime(w.date.year, w.date.month, w.date.day);
  if (last == null || day.difference(last).inDays == 1) { cur++; }
  else if (day.difference(last).inDays > 1) { cur = 1; }
  if (cur > bestStreak) bestStreak = cur;
  last = day;
}
```

This sees only the `workouts` table. **Rest days are invisible to it** — they are in
`SharedPreferences`, not SQLite. So a Mon-workout / Tue-rest / Wed-workout sequence is a *gap* here
(`inDays == 2` → `cur = 1`) while the persisted counter treats it as continuous. The two values
diverge by exactly the number of rest days taken.

Two further defects in this loop, independent of the definition mismatch:
- It inherits **BUG-03** verbatim (`difference(...).inDays` on truncated dates → DST-fragile).
- The `else if (... > 1)` has no `else` for `inDays == 0`: **two workouts on the same day** fall
  through both branches, leaving `cur` unchanged but reassigning `last` — benign here, but only by
  accident, and it means same-day doubles are neither counted nor reset.

There is also a layering objection: this is **domain logic living in a widget's `build` method**.
It re-runs on every rebuild, over the entire workout history, and it duplicates a concept the domain
layer already owns.

**Repro**
1. Work out Mon. Mark Tue as a rest day. Work out Wed.
2. Home: 🔥 current streak reads **2** (verified by trace: Mon→1, Tue rest sets
   `last_workout_date = Tue`, Wed sees `daysDiff == 1` → 2).
3. Best Streak reads **1** (Mon→Wed is `inDays == 2`, a gap, so `cur` resets).

**Proposed fix — reconciliation**
Pick one definition, put it in the domain layer, and compute both numbers from it.

I recommend: **a streak is a maximal run of consecutive days, each of which is either a workout day or
an explicitly-marked rest day.** That matches what the app *promises* the user ("Protect your streak.
Two rest days per week"), and makes "best" and "current" the same function evaluated over different
windows.

That requires rest days to be **queryable history**, not a single `last_rest_day_date` scalar — i.e.
persist rest days as rows (a `rest_days` table, or at minimum a date list). That is a schema change,
so it rides on BUG-04's migration. It would then let a `CalculateStreaks` use case return
`(current, best)` from one pass, delete the widget-embedded loop, and incidentally fix the phantom
calendar legend (BUG-24) by giving the calendar real rest-day data to render.

*Alternative — drop "Best Streak".* Cheapest, and honest. If you don't want the schema change now,
removing a knowingly-wrong number beats displaying it. Your call — it's a product decision.

*Alternative — make Best Streak match the naive workout-only definition and rename both.*
("Best workout run" vs "current streak".) Internally consistent, but confusing, and it keeps domain
logic in the widget.

**Behaviour change:** yes, materially — "Best Streak" values will change for any user who has taken
rest days. Needs explicit call-out.

**Blast radius** Home screen, streak datasource, schema (rest-day rows), calendar legend. This is the
largest *conceptual* fix in the report and overlaps heavily with Phase 3. **I recommend deferring the
full reconciliation to a Phase-3 feature and, for Phase 2, either removing Best Streak or fixing only
its DST bug** — flagging the disagreement in `project_context.md`. I want your decision here.

---

### <a name="bug-10"></a>BUG-10 — `markRestDay()` overwrites `last_workout_date`, conflating two facts

| Field | Content |
|---|---|
| **Severity** | High (one storage key encodes two different meanings; corrupts every consumer) |
| **Location** | `lib/data/datasources/streak_local_datasource.dart:87` |

**Symptom**
Indirect but pervasive: after marking a rest day, the app believes the user **worked out** that day.
This is the root enabler of BUG-07 (the workout guard can't work) and a contributor to BUG-09.

**Root cause**
```dart
await prefs.setInt(_restDaysRemainingKey, restDays - 1);
await prefs.setString(_lastRestDayKey, today.toIso8601String());
await prefs.setString(_lastWorkoutDateKey, today.toIso8601String());  // ← line 87
```

Line 87 is a deliberate trick to make the streak survive: `updateStreak` measures `daysDiff` from
`_lastWorkoutDateKey`, so moving that marker forward makes the *next* workout look consecutive. It
achieves the goal, but by **lying about what happened**. The key now means "last day the streak was
touched", while its name, and `updateStreak`'s use of it, both say "last day the user trained".

Consequences that follow directly:
- BUG-07's proposed guard ("did I already train today?") cannot be written against this key.
- BUG-09's two definitions diverge.
- The semantics are undiscoverable — nothing in the name or the types says a rest day writes here.

**Sub-finding: `markRestDay()` can be called before any streak exists.**
On a fresh install, `getRestDaysRemaining()` → `_initWeekIfNeeded()` seeds `rest_days_remaining = 2`,
so Home renders the button (`restDays > 0`) for a user who has **never worked out**. Tapping it
decrements to 1 and writes `_lastWorkoutDateKey = today`, while `streak_count` is still unset (0).
The user has "rested" from nothing and burned a token. There is no `streak_count == 0` guard anywhere
in `markRestDay`.

**Repro**
- *Conflation:* Mark a rest day today (no workout). Inspect prefs: `last_workout_date` == today.
- *No-streak case:* Fresh install → Home → tap "Mark Rest Day" → counter 2 → 1, streak still 0.

**Proposed fix**
Separate the two facts. Keep `_lastWorkoutDateKey` meaning **only** "last day a workout was logged",
and introduce an explicit notion of streak continuity — either:
- a `_lastStreakDayKey` ("last day the streak was kept, by training *or* resting"), which
  `updateStreak` measures against while `_lastWorkoutDateKey` stays truthful; or
- (better, and aligned with BUG-09) persist rest days as real rows and derive continuity.

Then gate `markRestDay` on `streak_count > 0` — or decide, as a product matter, that resting before
your first workout is meaningless and hide the button until the first workout exists.

**Behaviour change:** yes. Requires the BUG-07 / BUG-09 decisions; these three are one cluster and I'd
fix them in a single reasoned sequence rather than three unrelated commits.

**Blast radius** Entire `StreakLocalDatasourceImpl`; the prefs key contract (existing installs have
the conflated value already written — a prefs-level migration consideration).

---

### <a name="bug-11"></a>BUG-11 — DB failures render as "no workouts yet"; no logging anywhere in the app

| Field | Content |
|---|---|
| **Severity** | High (a read failure is indistinguishable from an empty account — the user believes their data is gone) |
| **Location** | `home_screen.dart:67` · `history_screen.dart:44` · `calendar_screen.dart:57` |

**Symptom**
If the database read throws — corrupt file, migration failure (BUG-04), platform with no sqflite
implementation (BUG-20), disk full — all three screens display their cheerful empty state:
**"No workouts yet. Start your first!"** The user concludes their entire training history has been
deleted. There is no error message, no retry, and nothing written to any log.

**Root cause**
All three sites collapse the error case into the empty case with the same idiom:

```dart
final workouts = snapshot.data ?? [];     // home_screen.dart:67
final workouts = snapshot.data ?? [];     // history_screen.dart:44
final workouts = snapshot.data ?? [];     // calendar_screen.dart:57
```

`AsyncSnapshot` has three terminal outcomes — `hasData`, `hasError`, and "done with neither". The
`?? []` fallback flattens `hasError` into the same branch as "no rows". `snapshot.error` is never
read; `snapshot.hasError` appears **nowhere** in the codebase.

History and Calendar do at least check `ConnectionState.waiting` and show a spinner
(`history_screen.dart:38`, `calendar_screen.dart:54`). **Home does not** — it renders
`snapshot.data ?? []` while the future is still pending, so on every load Home briefly flashes the
"No workouts yet" empty state before the data arrives. That is a second, user-visible bug in the same
three lines.

**Observability:** confirmed zero logging infrastructure. No `dart:developer`, no logging package, no
`FlutterError.onError` handler, no `BlocObserver`. The only `print` in the dependency chain is inside
`google_fonts`. When something fails in production there is no signal at all.

**Repro**
1. Corrupt the DB (or run on Web, per BUG-20).
2. Launch → Home shows "No workouts yet." Navigate to History → same. Calendar → empty month.
3. Nothing in the console indicates a failure occurred.

**Proposed fix**
Handle all three snapshot states explicitly at each site:

```dart
if (snapshot.connectionState == ConnectionState.waiting) return const _Loading();
if (snapshot.hasError) return _ErrorView(onRetry: _reload);   // distinct from empty
final workouts = snapshot.data ?? const [];
```

Add Home's missing `waiting` branch at the same time to kill the empty-state flash.

Separately, add a minimal `BlocObserver` (`onError`) and a `FlutterError.onError` hook so failures are
*recorded*. This is explicitly **not** "leave debug prints in" — it is one registered observer, not
instrumentation scattered through handlers.

*Why not centralise into a shared `AsyncView<T>` widget?* That would be a new abstraction with three
call sites — defensible, but your brief bars abstractions with one implementation and I'd rather
prove the pattern three times first and extract later if it stays identical.

**Behaviour change:** yes — DB errors will now show an error state with a retry instead of an empty
list. This is the fix.

**Blast radius** Three `FutureBuilder`s, plus `main.dart` for the error hooks.

---

### <a name="bug-12"></a>BUG-12 — **[NOT ON THE LIST]** Race in the `database` getter can open the database twice

| Field | Content |
|---|---|
| **Severity** | High (leaked connection; defeats the per-connection `PRAGMA` of BUG-05) |
| **Location** | `lib/data/datasources/workout_database.dart:10-14` |

**Symptom**
Intermittent and hard to attribute: a second database connection is opened and the first handle is
orphaned. Because `PRAGMA foreign_keys` is **per connection** (the whole premise of BUG-05), a leaked
or swapped connection is a correctness hazard, not just a resource leak.

**Root cause**
The lazy-init getter is not concurrency-safe:

```dart
Future<Database> get database async {
  if (_database != null) return _database!;      // ← check
  _database = await _initDB('gympulse.db');      // ← yields! then assigns
  return _database!;
}
```

There is an `await` between the null check and the assignment. Dart is single-threaded, but `async`
functions **interleave at every `await`**. Two callers that reach the getter before either has
finished `_initDB` will *both* observe `_database == null` and *both* call `openDatabase`. The second
assignment wins; the first `Database` object is retained by nobody but remains open.

This is not hypothetical — the app has concurrent first-touch callers by construction. On Home,
`didChangeDependencies` fires `sl<GetWorkouts>().call()` (`home_screen.dart:36`) and, on the very next
line, `StreakLoaded`. Navigating Home → Calendar quickly issues another `GetWorkouts` while the first
may still be in flight. Each ultimately reaches `WorkoutLocalDatasourceImpl._db`, which is this getter.

**Repro**
Hard to force by hand (the window is one event-loop turn). Deterministic in a test:
`await Future.wait([db.database, db.database])` with an instrumented `_initDB` counter → observe
`openDatabase` invoked twice.

**Proposed fix**
Cache the **`Future`**, not the resolved value — so every caller awaits the same in-flight operation:

```dart
static Future<Database>? _databaseFuture;

Future<Database> get database => _databaseFuture ??= _initDB('gympulse.db');
```

`??=` on the *future* is atomic with respect to the event loop: the assignment happens synchronously
before any `await` can interleave, so the second caller receives the first caller's future. This is
the standard Dart single-flight idiom.

One caveat to handle: if `_initDB` throws, the failed future is cached permanently and every
subsequent call gets the same error. Null the field in a `catchError` so a retry is possible — which
pairs directly with BUG-11's retry affordance.

**Behaviour change:** none observable in the happy path; removes a latent leak and enables retry.

**Blast radius** `workout_database.dart` only. Note `close()` (line 65-68) also does not clear the
cached handle, so a `close()` followed by any read returns a closed database — worth fixing in the
same commit.

---

### <a name="bug-13"></a>BUG-13 — `key: UniqueKey()` remounts and refetches `/history` on every Router rebuild

| Field | Content |
|---|---|
| **Severity** | Medium (broken UX: lost scroll position, spinner flash, redundant full-table reads) |
| **Location** | `lib/presentation/router.dart:74` |

**Symptom**
The History screen resets itself at unpredictable moments — scroll position jumps to the top, expanded
summary cards collapse, and a loading spinner flashes — without the user navigating anywhere.

**Root cause**
```dart
GoRoute(
  path: '/history',
  builder: (context, state) => HistoryScreen(key: UniqueKey()),
),
```

**[CHECKLIST CORRECT, mechanism confirmed]** The `UniqueKey()` is constructed **inside the builder
closure**, so a fresh, never-equal key is minted on every invocation of that builder.

When does the builder run? Traced through the resolved go_router **13.2.5** (not 13.2.0 as
`pubspec.yaml` suggests — the lockfile resolves to 13.2.5):

- `GoRouterDelegate.build` → `builder.build(context, currentConfiguration, routerNeglect)`
  (`delegate.dart:174-180`)
- → `RouteBuilder.build` → `_buildPageForGoRoute` (`builder.dart:230, 239`)
- → reads `match.route.builder` (`builder.dart:250`) and **calls it**.

`GoRouterDelegate` is a `RouterDelegate` hosted by the `Router` widget inside `MaterialApp.router`.
Its `build` re-runs whenever the `Router` element rebuilds — on delegate `notifyListeners()`, on any
ancestor rebuild, and on inherited-widget changes the `Router` subtree depends on. So the builder
runs far more often than "once per navigation".

Because `Widget.canUpdate` requires `runtimeType` **and** `key` equality, a new `UniqueKey` forces
Flutter to treat it as a *different widget*: the old `Element` is unmounted, `_HistoryScreenState` is
disposed, and a new State is created. `initState` then re-runs:

```dart
late final Future<List<Workout>> _workoutsFuture;
@override
void initState() {
  super.initState();
  _workoutsFuture = sl<GetWorkouts>().call();   // ← full DB read, every remount
}
```

`GetWorkouts` is an N+1 query — one `SELECT` on `workouts`, then one on `exercises` per workout, then
one on `sets` per exercise (`workout_local_datasource.dart:60-104`). So each spurious remount costs
`1 + N + (N × M)` queries. That is the real cost, and it grows with the user's history.

**Repro**
Open `/history`, scroll down, expand a card. Trigger any Router rebuild (a theme change is the
cleanest deterministic trigger). The screen resets and the spinner reappears.

**Proposed fix**
Delete the key: `builder: (context, state) => const HistoryScreen()`.

The key is solving a *different* problem badly — presumably "History shows stale data after a new
workout is saved". The correct fix for staleness is to make the data reactive rather than to destroy
the widget: either a `WorkoutBloc` the screen listens to (the unused `HistoryRequested` /
`WorkoutHistoryState` pair from BUG-24 was evidently intended for exactly this), or an explicit
refresh when the route is returned to.

*Why not `ValueKey(someRevisionCounter)`?* That remounts deliberately on data change, which is more
correct than `UniqueKey` but still throws away scroll state. Reactive state is better.

**Behaviour change:** yes, and it needs care — History will stop refetching on incidental rebuilds.
If anything currently *relies* on that accidental refresh to look correct, removing the key will make
staleness visible. Note `/active` finishes with `context.go('/')`, which tears down and rebuilds the
`/` route, so Home's refresh does not depend on this. History is reached via `context.push`, so its
staleness window is real and should be fixed deliberately, not via `UniqueKey`.

**Blast radius** `router.dart`, `HistoryScreen` state management. Interacts with BUG-24's dead
`HistoryRequested` event — this is the feature that event was written for.

---

### <a name="bug-14"></a>BUG-14 — One-shot load in `didChangeDependencies` (and a correction to the checklist)

| Field | Content |
|---|---|
| **Severity** | Medium (redundant work, duplicate loads; wrong lifecycle hook for the intent) |
| **Location** | `lib/presentation/screens/home_screen.dart:33-38` |

**Symptom**
Home re-issues a full workout query and re-dispatches `StreakLoaded` more often than it needs to.

**Root cause and a correction**

```dart
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  _workoutsFuture = sl<GetWorkouts>().call();          // full N+1 read
  context.read<StreakBloc>().add(const StreakLoaded()); // duplicate bloc load
}
```

`didChangeDependencies` fires (a) once after `initState`, and (b) **every time an `InheritedWidget`
this element depends on notifies of a change**.

**[CHECKLIST OVERSTATED]** The brief claims this *"fires on every dependency change (theme,
MediaQuery, keyboard open/close)"*. That is the general rule, but it is **not accurate for this
widget**, and the distinction is the whole point of the mechanism:

An element only depends on inherited widgets it has actually *subscribed to*, via an `of(context)`
call **using its own `BuildContext`**. In `_HomeScreenState.build` the only such call is
`Theme.of(context)` (line 51). `MediaQuery.of(context)` is never called with Home's context —
`Scaffold`, `ListView` etc. call it with *their own* descendant contexts, creating dependencies for
*those* elements, not Home's. And `context.read<StreakBloc>()` is `Provider.of(listen: false)`, which
deliberately does **not** register a dependency.

So Home's `didChangeDependencies` fires on **theme changes**, not on keyboard toggles. The practical
re-fire rate is much lower than the checklist implies. I'm flagging this because acting on the
checklist's version would mean chasing a symptom that does not occur.

It is still the wrong hook, for two real reasons:
1. **Intent mismatch.** These are one-shot initialisations. `initState` is where a load that should
   happen once belongs. Using `didChangeDependencies` says "re-run me when my dependencies change",
   which is not what is meant.
2. **Unguarded side effects.** Each firing starts an un-cancelled `Future` and dispatches a duplicate
   bloc event. `StreakLoaded` is *also* already dispatched by the router
   (`router.dart:43`: `sl<StreakBloc>()..add(const StreakLoaded())`), so the very first load is
   **always duplicated** — the bloc runs `getStreak()` twice on every cold start, and
   `_initWeekIfNeeded()` with it. That duplication is unconditional and happens today.

Note `_workoutsFuture` is declared nullable (`Future<List<Workout>>? _workoutsFuture`, line 24) and
assigned without `setState` — which works only because `didChangeDependencies` is already part of a
rebuild pass. Fragile by construction.

**Repro**
Cold-start the app with a breakpoint in `StreakBloc._onLoaded`: it is hit **twice** (once from the
router's cascade, once from `didChangeDependencies`).

**Proposed fix**
Move both to `initState`, and drop the now-redundant router-side dispatch (or keep the router's and
drop the screen's — one owner, not two):

```dart
@override
void initState() {
  super.initState();
  _userName = sl<SharedPreferences>().getString('user_name') ?? 'Athlete';
  _workoutsFuture = sl<GetWorkouts>().call();
}
```
`context.read` is legal in `initState` (it does not subscribe), so the bloc dispatch can move too —
but since the router already dispatches `StreakLoaded`, the cleanest resolution is to delete the
screen's copy entirely and let the route's `create:` cascade own it.

**Behaviour change:** Home stops refetching on theme change. Given Home is reached via `context.go`
(which rebuilds the route fresh), this does not introduce staleness in the current navigation flows —
but it interacts with BUG-13's staleness question and should be decided alongside it.

**Blast radius** `home_screen.dart`, and the duplicate dispatch in `router.dart:43`.

---

### <a name="bug-15"></a>BUG-15 — **[NOT ON THE LIST]** Onboarding name validation is bypassable by swiping

| Field | Content |
|---|---|
| **Severity** | Medium (validation is decorative; user lands in the app unnamed) |
| **Location** | `lib/presentation/screens/onboarding_screen.dart:46-70, 80-94` |

**Symptom**
The user swipes horizontally past the name page instead of tapping **Next**, never enters a name, taps
**Get Started**, and lands on Home greeted as *"Welcome, Athlete 👋"*. The "Please enter your name"
validation never fires.

**Root cause**
Validation is attached to the **button handler**, not to the **page transition**:

```dart
Future<void> _handleNext() async {
  if (_page == 0) {
    final name = _nameController.text.trim();
    if (name.isEmpty) { setState(() => _nameError = 'Please enter your name'); return; }
    ...
  }
  _pageController.nextPage(...);
}
```

But the `PageView.builder` (line 80) is constructed **without a `physics:` argument**, so it uses the
platform default scroll physics — it is freely swipeable. Swiping calls `onPageChanged` (line 83),
which only does `setState(() => _page = i)`. No validation, no guard.

`_complete()` then tolerates the empty name silently:
```dart
final name = _nameController.text.trim();
if (name.isNotEmpty) { await prefs.setString('user_name', name); }   // ← else: just skip
if (mounted) context.go('/');
```
`onboarding_complete` is set to `true` regardless, so the redirect guard (`router.dart:27-30`) will
never bring them back. The name is unrecoverable — **there is no settings screen to set it later.**

Related, covering the rest of the checklist's item A8:
- **Whitespace-only** (`"   "`) → `.trim()` → empty → correctly rejected *by the button path*, but
  bypassable by the same swipe.
- **Very long strings** → no `maxLength` on the `TextField` (line 201-208) and no truncation. The name
  is rendered in `displayMedium` (56px Playfair) at `home_screen.dart:118-120` inside a `Column` with
  no `overflow` handling → a long name overflows and produces a RenderFlex overflow stripe.

**Repro**
1. Fresh install → onboarding page 1. Leave the name field blank.
2. **Swipe** left twice (do not tap Next).
3. Tap **Get Started** → Home reads "Welcome, Athlete 👋". No name was ever required.

**Proposed fix**
Make the gate structural rather than advisory:
- `physics: const NeverScrollableScrollPhysics()` on the `PageView`, so the button is the only way
  forward and `_handleNext` is genuinely the single gate; **or**
- validate in `onPageChanged` and snap back to page 0 when the name is empty.

I prefer the first — it makes the invalid transition *unrepresentable* rather than detected and
undone, and it avoids a jarring snap-back animation.

Add `maxLength: 40` and `TextOverflow.ellipsis` on the greeting for the long-name case.

**Behaviour change:** yes — onboarding can no longer be swiped past without a name.

**Blast radius** `onboarding_screen.dart`; the greeting `Text` in `home_screen.dart`.

---

### <a name="bug-16"></a>BUG-16 — `setState` after `await` with no `mounted` guard

| Field | Content |
|---|---|
| **Severity** | Medium (exception on a disposed State; low probability, trivial fix) |
| **Location** | `lib/presentation/screens/onboarding_screen.dart:46-60` |

**Symptom**
`setState() called after dispose()` in the console, and a dropped frame, if the user leaves the
onboarding page during the `SharedPreferences` write.

**Root cause**
```dart
Future<void> _handleNext() async {
  if (_page == 0) {
    ...
    await sl<SharedPreferences>().setString('user_name', name);  // ← suspension point
    setState(() => _nameError = null);                           // ← no mounted guard
  }
  _pageController.nextPage(...);                                 // ← also unguarded
}
```

`await` on the prefs write yields to the event loop. If the widget is disposed during that window,
the resumed continuation calls `setState` on a defunct `State` — which throws — and then drives
`_pageController`, which was disposed at line 41.

I audited **every** `await`-then-touch-state path in the codebase for this pattern:
- `onboarding_screen.dart:69` — `_complete()` — **correctly guarded** with `if (mounted)`.
- `active_screen.dart:246` — post-frame callback — **correctly guarded** with `if (!context.mounted) return;`.
- `active_screen.dart:652-656` — nested post-frame + `Future.delayed` — **correctly guarded**
  (`if (!mounted) return;` and `widget.parentContext.mounted`).
- `home_screen.dart:36` — assigns a future without awaiting in the callback; no post-await `setState`.
- **`onboarding_screen.dart:54` is the only unguarded one.**

So this is a single miss in otherwise careful code, which is why it is Medium and not High.

**Repro**
Requires winning a narrow race (backgrounding the app during a prefs write). Deterministic in a widget
test by pumping a dispose between the await and its continuation.

**Proposed fix**
```dart
await sl<SharedPreferences>().setString('user_name', name);
if (!mounted) return;
setState(() => _nameError = null);
```
The guard must come *before* both the `setState` and the `_pageController` call, since both touch
disposed objects.

**Behaviour change:** none observable.

**Blast radius** One method.

---

### <a name="bug-17"></a>BUG-17 — System-back out of `/active` silently discards an in-progress workout

| Field | Content |
|---|---|
| **Severity** | Medium (data loss, but user-initiated and currently unwarned) |
| **Location** | `lib/presentation/screens/active_screen.dart:20-36` · `lib/presentation/router.dart:53-71` |

**Symptom**
Mid-workout, the user swipes back (iOS edge-swipe / Android system back / the AppBar back button).
The `/active` route pops instantly. Every logged set is gone. No confirmation, no draft, no undo.

**Root cause**
`ActiveScreen` is a plain `Scaffold` (line 25) with **no `PopScope`** (Flutter 3.41's replacement for
`WillPopScope`) and no `canPop: false` / `onPopInvokedWithResult` handling. Nothing intercepts the pop.

The in-progress workout lives **only** in `WorkoutInProgressState` inside a `WorkoutBloc` that the
route's `BlocProvider` created (`router.dart:56-59`). `BlocProvider` disposes the bloc when its
element unmounts, so popping the route closes the bloc and the state is unrecoverable. There is no
persistence of a draft anywhere — `saveWorkout` is only ever called from `_onFinished`.

Note the screen *does* guard the deliberate exit path carefully: `_FinishButton` has a two-step
confirm (`_confirming`, line 687) and warns on an empty exercise list and an unstarted timer
(lines 689-723). All that care is bypassed entirely by the system back gesture.

Also note `context.go('/active')` (`home_screen.dart:256`) **replaces** rather than pushes, so there
is no `/` route beneath to pop back to — the pop behaviour here is whatever go_router's
`ImperativeRouteMatch` handling decides, which makes the outcome less predictable than a normal pop.

**Repro**
1. Start a workout, add an exercise, log three sets.
2. Swipe back / press system back.
3. Home. The workout is gone; History shows nothing.

**Proposed fix**
Wrap the screen in a `PopScope`:

```dart
PopScope(
  canPop: false,
  onPopInvokedWithResult: (didPop, _) async {
    if (didPop) return;
    final discard = await _confirmDiscard(context);
    if (discard && context.mounted) context.go('/');
  },
  child: Scaffold(...),
)
```

`canPop: false` tells the *framework* to route the gesture to the callback instead of popping — which
is why this must be `PopScope` and not a `WillPopScope`-style async veto (removed in recent Flutter:
predictive-back on Android needs to know up front whether a pop is allowed, which is the whole reason
for the API change).

Gate it on `state is WorkoutInProgressState && state.exercises.isNotEmpty` so an empty session still
backs out freely without a nuisance dialog.

*The stronger fix* is a **persisted draft** that survives both back-navigation and process death —
which is exactly Phase 3 candidate "persisted in-progress workout draft". `PopScope` is the correct
Phase-2 stopgap; the draft is the real answer.

**Behaviour change:** yes — back with logged sets now prompts instead of discarding.

**Blast radius** `active_screen.dart`. Overlaps a Phase-3 candidate.

---

### <a name="bug-18"></a>BUG-18 — Weekly progress bar contradicts the rest-day model, and measures a rolling 168 hours

| Field | Content |
|---|---|
| **Severity** | Medium (wrong data shown; two features disagree about what "this week" means) |
| **Location** | `lib/presentation/screens/home_screen.dart:73-77, 197` |

**Symptom**
"3 / 5 days this week" can include a workout from *last* Tuesday, and the denominator disagrees with
the rest-day allowance the onboarding screen promises.

**Root cause**
Two separate defects in five lines.

**(1) The 5 vs 7-minus-2 question — these actually agree.**
```dart
final weekProgress = (thisWeek / 5).clamp(0.0, 1.0);
...
Text('$thisWeek / 5 days this week')
```
7 days − 2 rest days = 5 training days. So the `5` and the `2` **are consistent** as a model. The
problem is that neither is derived from the other: `5` is a bare literal here and `2` is a bare
literal three times in the datasource (BUG-19). Change the rest allowance to 3 and this bar silently
becomes wrong. They agree today by coincidence, not by construction.

**[CHECKLIST PARTLY WRONG]** The brief asks to *"verify these two concepts agree"* and flags a
possible **divide by zero**. They do agree, and **divide-by-zero is impossible** — the denominator is
the integer literal `5`. The `.clamp(0.0, 1.0)` is present and correct, and `LinearProgressIndicator`
receives a value in range. Verified: `(0/5).clamp(0.0,1.0) == 0.0`. No bug there.

**(2) The real defect — "this week" is a rolling 168-hour window, not a week.**
```dart
final thisWeek = workouts.where((w) {
  final diff = now.difference(w.date).inDays;
  return diff < 7;
}).length;
```
This counts workouts in the **last 7 × 24 hours from this instant**, which is not a calendar week and
not the rest-day week either. Consequences:
- On a Tuesday, it includes *last* Wednesday — days the user does not think of as "this week".
- It disagrees with `_initWeekIfNeeded`'s week (which starts from the first day the user ever opened
  the app — BUG-22), *and* with any ISO Monday-start week.
- It inherits **BUG-03**: `now.difference(w.date).inDays` compares a raw `DateTime.now()` timestamp
  against a stored workout timestamp with no truncation at all, so a workout logged 7 hours ago at
  23:00 yesterday and one logged 6 days 20 hours ago both land inside the window by clock arithmetic
  rather than by date.

So the app has **three** incompatible definitions of "week": this rolling window, the datasource's
rolling `>= 7` window from an arbitrary anchor (BUG-22), and the user's mental calendar week.

**Repro**
1. Work out last Wednesday and this Monday and Tuesday.
2. On Tuesday, Home reads "3 / 5 days this week" — including last Wednesday.

**Proposed fix**
Define the week **once**, in the domain, and derive both the bar and the rest allowance from it.
I recommend an explicit, user-legible calendar week (Monday 00:00 local → Sunday 23:59 local), and a
named constant pair:

```dart
const kTrainingDaysPerWeek = 5;
const kRestDaysPerWeek = 2;   // kTrainingDaysPerWeek + kRestDaysPerWeek == 7
```
with the count computed by civil-date comparison (per BUG-03) against the current week's Monday.

*Alternative — keep the rolling window but label it honestly* ("3 workouts in the last 7 days"). Cheap
and not wrong, but it leaves three definitions of "week" in the app.

**Behaviour change:** yes — the "this week" count will change for most users. Call out explicitly.

**Blast radius** Home screen; the week definition shared with `_initWeekIfNeeded` (BUG-22) and the
constants of BUG-19. This cluster (18/19/22) is really one fix: *define the week and the allowance in
one place*.

---

### <a name="bug-19"></a>BUG-19 — The magic number `2` is duplicated in three places

| Field | Content |
|---|---|
| **Severity** | Medium (all copies currently agree; nothing enforces that they continue to) |
| **Location** | `streak_local_datasource.dart:27, 83, 98, 105` · `home_screen.dart:137` · `onboarding_screen.dart:30` |

**Symptom**
None today. It is a latent inconsistency: changing the rest-day allowance requires finding six
literals across three files, and missing one produces a subtle, hard-to-trace divergence.

**Root cause**
I checked every copy, as asked. **All copies currently agree on the value 2:**

| Site | Code | Role |
|---|---|---|
| `streak_local_datasource.dart:27` | `prefs.getInt(_restDaysRemainingKey) ?? 2` | read default |
| `streak_local_datasource.dart:83` | `prefs.getInt(_restDaysRemainingKey) ?? 2` | read default (duplicate of above) |
| `streak_local_datasource.dart:98` | `prefs.setInt(_restDaysRemainingKey, 2)` | first-run seed |
| `streak_local_datasource.dart:105` | `prefs.setInt(_restDaysRemainingKey, 2)` | weekly reset |
| `home_screen.dart:137` | `state is StreakLoadedState ? state.restDaysRemaining : 2` | **UI fallback** |
| `onboarding_screen.dart:30` | `'Two rest days per week — use them wisely.'` | user-facing copy (spelled out) |

Two observations beyond the count:
- `home_screen.dart:137` is the worst copy: it is a **UI fallback for a non-loaded state**, so before
  `StreakLoaded` resolves, Home optimistically renders "🌿 2 rest days left" and shows the Mark Rest
  Day button — even for a user who has zero remaining. A brief but real display of wrong data.
- The onboarding string hard-codes the English word "Two", so it will not track a constant at all.

And per BUG-18, the *related* constant `5` lives in `home_screen.dart:77,197` with no link to these.

**Repro** N/A (latent).

**Proposed fix**
A single named constant in the data layer, which the datasource uses for all four sites:

```dart
static const defaultRestDaysPerWeek = 2;
```

For the UI fallback, the right fix is not to share the constant but to **stop guessing**: render a
loading/placeholder state until `StreakLoadedState` arrives, rather than defaulting to `2`. Sharing
the constant would make the wrong number consistent; not displaying a number until it is known is
correct.

Note this constant belongs in the datasource (it is a storage default), **not** in `domain/` — and it
must not be imported by `home_screen.dart`, since presentation importing data would violate the
dependency rule. That is precisely why the UI fallback should be a loading state instead.

**Behaviour change:** the Home card will show a placeholder instead of "2" for the brief pre-load
window.

**Blast radius** Streak datasource, Home card. Part of the 18/19/22 cluster.

---

### <a name="bug-20"></a>BUG-20 — Web / Windows / Linux are configured platforms but sqflite has no implementation there

| Field | Content |
|---|---|
| **Severity** | Medium (the app is non-functional on three of six advertised platforms) |
| **Location** | `pubspec.yaml:24` · `README.md` ("Supports Android, iOS, macOS, Web, Windows, and Linux") · `web/`, `windows/`, `linux/` |

**Symptom**
`flutter run -d chrome` builds and launches. The UI renders (onboarding works — it only uses
`SharedPreferences`, which *does* have a web implementation). The moment anything touches the
database — Home's `GetWorkouts`, finishing a workout — it throws `MissingPluginException`. Per
BUG-11, the user sees **"No workouts yet"** instead of an error. Saving a workout fails with the
generic "Failed to save workout" snackbar, forever.

**Root cause**
Confirmed from `pubspec.lock` — the resolved sqflite dependency tree contains **only**:

```
sqflite 2.4.2+1
  sqflite_android          ← Android
  sqflite_darwin           ← iOS + macOS
  sqflite_common
  sqflite_platform_interface
```

There is **no `sqflite_common_ffi`** (desktop) and **no `sqflite_common_ffi_web`** (web) — verified by
grep across `pubspec.yaml` and `pubspec.lock`. `sqflite` is a federated plugin: with no registered
implementation for the running platform, the method-channel call finds no handler and throws
`MissingPluginException`.

There is also no `databaseFactory` override anywhere in `lib/` (grepped) — which is how one would
wire `databaseFactoryFfi` / `databaseFactoryFfiWeb` if desktop or web support were intended.

So: **Android and iOS work. macOS works** (`sqflite_darwin` covers it — worth noting, since the
checklist lumps macOS in with the broken desktop platforms). **Windows, Linux and Web are broken.**

The `windows/`, `linux/` and `web/` directories exist only because `flutter create` scaffolds all
platforms by default. Nothing else supports the README's claim.

**Repro**
`flutter run -d chrome` → complete onboarding → Home renders "No workouts yet" → start a workout, log
a set, Save & Finish → "Failed to save workout". Console shows `MissingPluginException(No
implementation found for method openDatabase on channel com.tekartik.sqflite)`.

**Proposed fix — this is a product decision, so I am not choosing it for you**

- **(a) Narrow the claim.** Remove `web/`, `windows/`, `linux/` from the repo and correct the README to
  "Android, iOS, macOS". Zero new dependencies, zero new code, and the app stops advertising something
  it cannot do. **My recommendation** for a learning project whose stated goal is architecture, not reach.
- **(b) Add the implementations.** `sqflite_common_ffi` (desktop) + `sqflite_common_ffi_web` (web),
  plus a platform-switched `databaseFactory` assignment in `main()` before `init()`. This is two new
  dependencies and a web-worker/wasm asset setup step for the web build. It earns its weight *only* if
  you actually want to ship those targets. It would also be architecturally instructive — it forces the
  `databaseFactory` seam, which would make the DB injectable and **directly enable the sqflite unit
  tests** Phase 2 wants (today `WorkoutLocalDatasourceImpl` is untestable off-device for exactly this
  reason).

That last point is worth weighing: (b) is the option that improves testability. If you want real
datasource tests rather than only `StreakLocalDatasourceImpl` tests, `sqflite_common_ffi` as a
**dev_dependency** is the standard way, and that is a much smaller commitment than shipping web.

**Behaviour change:** depends on the option chosen.

**Blast radius** (a) README + directory removal. (b) `pubspec.yaml`, `main.dart`, web asset config.

---

### <a name="bug-21"></a>BUG-21 — google_fonts fetches over HTTP; the offline-first claim fails on cold first launch

| Field | Content |
|---|---|
| **Severity** | Medium (degraded typography on first run; a network dependency in an "offline-first" app) |
| **Location** | `pubspec.yaml:22` (no `flutter: fonts:` or `assets:` section) · every `GoogleFonts.*` call in `main.dart` and 10 other files |

**Symptom**
A user installs the app and opens it for the first time **with no network** (on a plane, which is a
realistic gym-app scenario). The entire type system — Playfair Display headings, DM Sans body —
silently falls back to the platform default font. The app looks wrong. The console fills with
`Error: google_fonts was unable to load font ...`. On a *later* launch with network, it corrects itself.

**Root cause**
Confirmed from the resolved `google_fonts 6.3.3` source. `loadFontIfNecessary` tries three sources in
order (`google_fonts_base.dart:150-184`):

1. `rootBundle.load(assetPath)` — bundled assets. **`pubspec.yaml` declares no `fonts:` and no
   `assets:` section** (verified), so this always misses.
2. `loadFontFromDeviceFileSystem` — a previously-downloaded cache. Empty on first launch.
3. `_httpFetchFontAndSaveToDevice` — **an HTTP request to fonts.gstatic.com**, gated on
   `GoogleFonts.config.allowRuntimeFetching`, which defaults to `true` and is never set in this app.

With no network, step 3 throws, and the `catch` at line 185 swallows it into a `print` and returns —
so the `TextStyle` is returned without the font family applied. No crash, silent visual degradation.

This is the one finding where "offline-first" is contradicted by a **dependency's default behaviour**
rather than by app code. Everything else in the app genuinely is offline (sqflite + SharedPreferences).

**Repro**
1. Fresh install (or clear app data), device in airplane mode.
2. Launch. Headings render in the system serif/sans fallback, not Playfair/DM Sans.
3. Console: `Error: google_fonts was unable to load font PlayfairDisplay because the following
   exception occurred: ...`

**Proposed fix**
Bundle the fonts and turn off runtime fetching:

1. Download the four needed faces (Playfair Display 600/700, DM Sans 400/500/600) into `assets/fonts/`.
2. Declare them in `pubspec.yaml` under `flutter: fonts:`.
3. `GoogleFonts.config.allowRuntimeFetching = false;` in `main()` — which, per line 179, converts a
   silent fallback into a **loud exception** if a face is ever missing from assets. That is the right
   trade for an offline-first app: fail loudly in development rather than silently in production.

This costs roughly 300-600 KB of APK size and removes a network dependency from first launch.

*Alternative — drop `google_fonts` entirely* and declare the fonts as plain Flutter assets with a
`fontFamily` in the theme. That removes a dependency altogether and is arguably the cleanest outcome,
since the package's *only* value here is the runtime download this fix disables. Worth considering —
though it touches all 11 files that call `GoogleFonts.*`, so it is a refactor, not a bug fix, and per
your rules it must not be bundled into this commit.

**Behaviour change:** typography becomes correct and deterministic on first launch.

**Blast radius** `pubspec.yaml`, `main.dart`, plus new asset files. No Dart logic changes.

---

### <a name="bug-22"></a>BUG-22 — `_initWeekIfNeeded()`'s rolling window never aligns to a real week

| Field | Content |
|---|---|
| **Severity** | Medium (rest allowance resets on an arbitrary day; boundary is off by the DST bug) |
| **Location** | `lib/data/datasources/streak_local_datasource.dart:91-107` |

**Symptom**
The user's two rest days refill on a seemingly random weekday — whichever day they first opened the
app — and never on Monday. Two users who installed on different days have different "weeks".

**Root cause**
I checked the `>= 7` boundary explicitly, as asked.

```dart
Future<void> _initWeekIfNeeded() async {
  final today = DateTime(now.year, now.month, now.day);
  final weekStartStr = prefs.getString(_weekStartDateKey);

  if (weekStartStr == null) {
    await prefs.setString(_weekStartDateKey, today.toIso8601String());  // ← anchor = first run
    await prefs.setInt(_restDaysRemainingKey, 2);
    return;
  }

  final weekStart = DateTime.parse(weekStartStr);
  if (today.difference(weekStart).inDays >= 7) {
    await prefs.setString(_weekStartDateKey, today.toIso8601String());  // ← re-anchor = today
    await prefs.setInt(_restDaysRemainingKey, 2);
  }
}
```

**Boundary verdict (6 / 7 / 8 days):**
- **6 days** → `inDays == 6` → `>= 7` false → no reset. Correct for a 7-day window.
- **7 days** → `inDays == 7` → true → resets. Correct — day 7 starts the new week.
- **8 days** → `inDays == 8` → true → resets, **and re-anchors `week_start` to today (day 8)**, not to
  day 7. So a user who does not open the app on day 7 silently gets an 8-day week. The window
  **drifts forward** by however long the app went unopened. Over months of irregular use, the "week"
  wanders arbitrarily.

  This is the real defect and it is a direct consequence of re-anchoring to `today` rather than
  advancing `weekStart` by whole weeks (`weekStart.add(Duration(days: 7 * (elapsed ~/ 7)))`).

**Does the allowance reset correctly rather than carrying over?** Yes — it is a hard
`setInt(_restDaysRemainingKey, 2)`, not an increment, so unused rest days do **not** accumulate.
That part is correct. (Whether it *should* carry over is a product question; not carrying over seems
right.)

**Two further problems:**
1. **Lazy evaluation.** `_initWeekIfNeeded` only runs when something calls `getRestDaysRemaining`,
   `updateStreak`, or `markRestDay`. A user who does not open the app for 10 days gets their reset at
   *first open on day 10*, re-anchored to day 10.
2. **BUG-03 again.** `today.difference(weekStart).inDays` is the same DST-fragile physical-duration
   arithmetic, so the boundary can fire a day late across a spring-forward.

And per BUG-18, this window is a *third* definition of "week", incompatible with Home's rolling
168-hour one.

**Repro**
1. Install on a Thursday. `week_start = Thursday`.
2. Use the app for 5 days, then do not open it for 4 days.
3. Open on day 9. Rest days reset, and `week_start` is now that day — a different weekday than before.
   Repeat, and the anchor keeps drifting.

**Proposed fix**
Anchor the week to a **fixed calendar boundary** (ISO Monday) rather than to first-run, and advance in
whole weeks:

```dart
DateTime _startOfWeek(DateTime d) =>
    DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));  // Monday
```
Reset when `_startOfWeek(today) != storedWeekStart`, then store `_startOfWeek(today)`. This is
drift-free by construction (no accumulating remainder), matches the user's mental model, and makes
Home's bar and the allowance share one definition — resolving the 18/19/22 cluster together.

(The `Duration(days:)` subtraction here is safe from the DST bug because the result is immediately
re-truncated to a civil date and compared by *equality*, not by `inDays` magnitude — but I would use
the civil-date helper from BUG-03 for consistency.)

**Behaviour change:** yes — the reset day moves to Monday for every existing user, and one user will
see a one-off short or long week during the transition. Worth calling out.

**Blast radius** Streak datasource; shared week definition with Home (BUG-18).

---

### <a name="bug-23"></a>BUG-23 — Zero / negative reps and weights reach the database

| Field | Content |
|---|---|
| **Severity** | Medium (nonsense data persisted; corrupts volume aggregates) |
| **Location** | `lib/presentation/widgets/exercise_log_card.dart:36-44` |

**Symptom**
A user can log "0 reps × 0 kg" or "-5 reps × -20 kg". Both are accepted, rendered, saved, and folded
into total volume — where a negative set **subtracts** from the workout's volume, making the summary
card understate or even go negative.

**Root cause**
Same single guard as BUG-02 — `if (reps == null || weight == null) return;` — with no range check.
Verified parse behaviour:

```
int.tryParse(0)      = 0        ← accepted
int.tryParse(-5)     = -5       ← accepted
double.tryParse(-5)  = -5.0     ← accepted
int.tryParse(007)    = 7        ← harmless, leading zeros normalise
```

Whitespace is handled — both call `.trim()` first (`double.tryParse('  12  ')` → `12.0` verified) — so
the checklist's whitespace concern is **not** a bug here.

The schema does not defend either: `reps INTEGER NOT NULL, weight REAL NOT NULL`
(`workout_database.dart:55-56`) has no `CHECK` constraint. So the database will happily accept
`reps = -5`.

Downstream, `_totalVolume` folds `set.reps * set.weight` (`workout_summary_card.dart:37`,
`calendar_screen.dart:321`) with no filtering — negatives subtract.

I am separating this from BUG-02 because the *fix* is the same edit but the *severity* differs: BUG-02
causes unrecoverable save failure (Critical), this causes wrong-but-saveable data (Medium). They
should be fixed in one commit.

**Repro**
1. Log a set with reps `10`, weight `100`. Volume shows `1000 kg`.
2. Log a second set on the same exercise: reps `-10`, weight `100`.
3. Volume now reads `0 kg`.

**Proposed fix**
Range-validate at input (shared with BUG-02), and add `CHECK` constraints to the schema as
defence-in-depth when the BUG-04 migration lands:

```sql
reps INTEGER NOT NULL CHECK (reps > 0),
weight REAL NOT NULL CHECK (weight >= 0)
```

The `CHECK` is not a substitute for input validation (it surfaces as a save-time failure, which is
BUG-02's failure mode), but it makes the invariant explicit in the schema and catches any future code
path that bypasses the widget.

**Behaviour change:** yes — zero/negative sets are rejected with a visible message.

**Blast radius** `_submitSet` + its `TextField`s; schema `CHECK`s ride with BUG-04's migration.

---

### <a name="bug-24"></a>BUG-24 — Dead code and inconsistencies (list only — **no deletions without your confirmation**)

| Field | Content |
|---|---|
| **Severity** | Low |
| **Location** | Various — enumerated below |

Per your rule, **I have deleted nothing.** This is the list and the argument; I will wait.

**(a) Four orphaned widgets** — verified zero references outside their own definition files:

| File | LOC | Verdict |
|---|---|---|
| `widgets/streak_badge.dart` | 39 | **Delete.** Zero refs. Also visually obsolete — hardcoded `0xFF16213E` / `0xFFE94560` are from an abandoned dark palette that matches nothing in the current theme. |
| `widgets/streak_card.dart` | 68 | **Delete.** Zero refs. Superseded by the inline streak `Card` in `home_screen.dart:138-237`. |
| `widgets/timer_display.dart` | 28 | **Delete.** Zero refs. Its `_format` logic is duplicated inline in three places (see (f)). |
| `widgets/exercise_card.dart` | 82 | **Delete.** Zero refs. Superseded by `exercise_log_card.dart`. Note it hardcodes `'Weight (kg)'` (line 39) — it predates the unit toggle entirely, so reviving it would reintroduce BUG-01. |

**Argument for deletion:** all four are unreachable, none is referenced by tests (the only test is a
placeholder), and three of the four encode *superseded* design decisions (old palette, hardcoded kg).
Keeping them means the next reader must determine reachability themselves. Git history preserves them
if ever wanted. `StreakCard` is the only one with any argument for keeping — it is a reasonable
extraction of the Home streak card, and if you ever want that card reused, it is a starting point.

**(b) Unused JSON codec** — `ExerciseSetModel.toJson/fromJson`, `ExerciseModel.toJson/fromJson`,
`WorkoutModel.toJson/fromJson` (`exercise_model.dart:6-12,24-34`, `workout_model.dart:14-29`).
Verified: zero callers outside the model files, and **`dart:convert` is never imported anywhere in
`lib/`**. Persistence goes through hand-written column maps in `workout_local_datasource.dart`, not
JSON.

**Argument: keep, do not delete.** Unlike (a), this is a *complete and correct* serialisation layer
with an obvious near-term purpose — it is exactly what a JSON export/import feature needs (one of your
Phase-3 candidates). Deleting it to re-add it in Phase 3 is churn. I'd leave it and note it in
`project_context.md` as "intentionally unused, reserved for export/import". Note `WorkoutModel.fromJson`
already carries a defensive `json['durationSeconds'] as int? ?? 0` (line 18) suggesting a prior
format migration was anticipated.

**(c) `WorkoutBloc.HistoryRequested` / `WorkoutHistoryState`** — `workout_event.dart:48-50`,
`workout_state.dart:49-56`, handler at `workout_bloc.dart:26,92-98`. The handler is registered and
functional; nothing ever dispatches the event. `HistoryScreen` bypasses the bloc entirely and calls
`sl<GetWorkouts>()` directly from `initState`.

**Argument: keep, and *use* it.** This is the intended fix for BUG-13 — History should be
bloc-driven rather than remounted via `UniqueKey`. Deleting it removes the better design. Note the
handler has a real defect if revived: no `try/catch`, so a DB failure becomes an unhandled exception
in the bloc (unlike `_onFinished`, which is guarded). Fix that when wiring it up.

**(d) `flutter_animate: ^4.5.0`** (resolved 4.5.2) — verified: no import of `flutter_animate`, no
`.animate()` call anywhere in `lib/`. A declared, downloaded, entirely unused dependency.
**Argument: delete from `pubspec.yaml`.** It is pure weight. Trivially re-addable.

**(e) Calendar legend promises rest-day markers that are never rendered** —
`calendar_screen.dart:226-234` renders a legend dot labelled **"Rest day"**, but `markerBuilder`
(lines 194-209) only ever draws a marker for `workoutsByDay`, and the screen never reads rest-day data
(which lives in `SharedPreferences`, not in the `workouts` query). So the legend describes a feature
that does not exist. **This is arguably not "dead code" but a wrong-data bug** — the user is told to
look for something that will never appear.
**Argument: either render real rest-day markers (requires BUG-09's rest-day rows) or remove the
legend entry.** Removing is the honest Phase-2 fix; rendering is the Phase-3 one.

**(f) Three near-duplicate hand-rolled date formatters** — plus, I found, **three duplicate
duration formatters** the checklist did not mention:

| Kind | Location | Format |
|---|---|---|
| Date | `home_screen.dart:43-47` | `'Monday, Jan 5'` — full day, short month |
| Date | `workout_summary_card.dart:30-34` | `'Mon, Jan 5'` — short day, short month |
| Date | `calendar_screen.dart:83-87` | `'Monday, January 5'` — full day, full month |
| Duration | `active_screen.dart:57-61` | `mm:ss` |
| Duration | `calendar_screen.dart:268-272` | `mm:ss` (identical) |
| Duration | `workout_summary_card.dart:24-28` | `mm:ss` (identical) |

The three duration formatters are **byte-identical**. The three date formatters differ only in which
abbreviation arrays they use.

Two real bugs hide in here:
- All six are **hardcoded English** with no `intl` / locale support.
- The `mm:ss` duration formatters break for workouts over 60 minutes: a 90-minute workout renders as
  `90:00`, not `1:30:00`. `durationSeconds ~/ 60` is not clamped to an hour.

**Argument: consolidate — but not in a bug-fix commit.** Per your rules this is a refactor and must be
its own commit. The duration formatters are the stronger case (byte-identical, and they share the
>60min bug). `TimerDisplay` from (a) is *almost* the right home for the duration one — which is an
argument for keeping that file rather than deleting it, if we consolidate.

**Blast radius** None for (a)/(d). (c)/(e) interact with BUG-13/BUG-09.

---

### <a name="bug-25"></a>BUG-25 — Rest-timer custom duration is unbounded and commits on every keystroke

| Field | Content |
|---|---|
| **Severity** | Low (broken UX; no data impact — rest duration is never persisted) |
| **Location** | `lib/presentation/screens/active_screen.dart:526-537` |

**Symptom**
Typing `120` into "Custom seconds" sets the duration to `1`, then `12`, then `120` as the user types.
If they mistype `99999`, the timer will run for 27 hours with no upper bound.

**Root cause**
```dart
onChanged: (v) {
  final n = int.tryParse(v);
  if (n != null && n > 0) setState(() => _selectedDuration = n);
},
```
`onChanged` fires per keystroke, so every intermediate prefix is committed as a real selection. There
is no upper bound and no `onSubmitted`/commit affordance.

The downstream consequence is contained: `_selectedDuration` feeds `RestTimerStarted(duration)`, and
`_onStarted` builds `Stream.periodic(...).take(duration)` (`rest_timer_bloc.dart:26-29`). A huge
`duration` means a very long-lived subscription, but it *is* cancelled on `close()` (line 74) and on
`RestTimerReset`, and the sheet's `whenComplete` fires a reset (`active_screen.dart:264`) — so it
cannot leak past the sheet. No data is written. Hence Low.

**Repro**
Open the rest timer sheet, type `120` in Custom seconds, and watch the ring's denominator jump
1 → 12 → 120 as you type.

**Proposed fix**
Clamp and defer: `keyboardType: TextInputType.number` is already set; add
`inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)]`,
clamp to a sane range (say 5-3600), and commit on `onSubmitted` / on Start rather than `onChanged`.

**Behaviour change:** yes — the custom duration applies when committed rather than per keystroke.

**Blast radius** One `TextField` in the rest-timer sheet.

---

## 3. Checklist verdicts — including the items that are NOT bugs

You asked for an explicit verdict on every item, including what I checked when I found nothing. Items
that became findings are cross-referenced; the rest are resolved here with their evidence.

### A — Data correctness

| # | Item | Verdict |
|---|---|---|
| A1 | Weight units display-only | ✅ **Confirmed** → [BUG-01](#bug-01). Historical data is **relabelled, not converted**. Volume does not currently sum across mixed units (the unit is global), but only because per-set units don't exist — which is the bug. Recommended fix: **(b) canonical kg + convert at the display boundary**, argued in full in BUG-01. |
| A2 | Date is `now()` at finish | ✅ **Confirmed** → [BUG-06](#bug-06). Midnight crossing misfiles the workout; affects streak, calendar grouping and history sort. |
| A3 | `PRAGMA foreign_keys` placement | ⚠️ **Confirmed, but the checklist's diagnosis is wrong** → [BUG-05](#bug-05). The pragma exists **twice**. The copy in `onCreate` (line 29) is a **silent no-op** (proved: pragma inside a transaction → `fk=0`), but the copy at line 24 runs outside any transaction on every launch and **does** work. So FK enforcement is **currently ON**, contrary to the checklist's prediction. Still belongs in `onConfigure`. |
| A4 | `ConflictAlgorithm.replace` orphans/duplicates | ✅ **Not a bug today — and I proved both branches.** With FK **ON** (the current state), `INSERT OR REPLACE` on a `workouts` row **cascade-deletes** its exercises and sets before the loop re-inserts them → clean replace, no orphans, no duplicates (verified: children `1 → 0`). With FK **OFF**, children survive and the re-insert **duplicates** every exercise and set (verified: children stay `1`, then the loop adds more). No orphans arise in either case because the PK is unchanged, so children still point at a live parent. **Documented as required**: the save path's correctness depends entirely on BUG-05's line 24. Nothing currently triggers a replace (every save mints a fresh `Uuid().v4()`), but workout-edit — a Phase-3 candidate — would. |
| A5 | Schema v1, no `onUpgrade` | ✅ **Confirmed** → [BUG-04](#bug-04). Bumping `version` without `onUpgrade` throws `ArgumentError` from sqflite; it does **not** silently fall back to `onCreate`. Combined with BUG-11, the user sees "No workouts yet" rather than an error. |
| A6 | `ORDER BY date DESC` on ISO8601 TEXT | ✅ **Not a bug. Verified lexicographic sortability empirically.** All writes use `date.toIso8601String()` on a **local** `DateTime` (`workout_local_datasource.dart:25`), producing `2025-05-01T10:00:00.100` — fixed-width through the millisecond field, **no offset suffix**. Dart appends 3 further digits only when microseconds are non-zero (`...100500`, length 26 vs 23) — verified — but because the millisecond field is always zero-padded to 3 digits, the shorter string is a proper prefix of an equivalent longer one, so ASCII ordering still matches chronological ordering (verified: `.100` sorts before `.100500`). Format is consistent across all rows: there is exactly one write site and it never produces UTC (`Z`) strings. **Caveat worth noting, not a bug:** since the stored strings are local wall-clock with no offset, a user who changes timezone gets rows ordered by wall-clock rather than by true instant. Ordering within a timezone is correct. |
| A7 | Set input validation | ✅ **Confirmed, split by severity** → [BUG-02](#bug-02) (Critical: `NaN` → `NOT NULL` violation → workout permanently unsaveable; `Infinity` and `1e309` also pass) and [BUG-23](#bug-23) (Medium: zero/negative reps and weight). **Whitespace is NOT a bug** — both parsers are given `.trim()`ed input (verified `double.tryParse('  12  ') == 12.0`). `double.tryParse` failures *are* handled (null-check), but that check is the *only* validation. Absurd values: unbounded, no `CHECK` constraints in the schema. |
| A8 | Onboarding name edge cases | ✅ **Confirmed, and worse than described** → [BUG-15](#bug-15). Empty-after-trim and whitespace-only **are** rejected — but only on the button path; the `PageView` has default (swipeable) physics, so the entire validation is bypassable by swiping. Very long strings: no `maxLength`, and the greeting renders in 56px Playfair with no overflow handling. |

### B — Streak & rest-day algorithm

| # | Item | Verdict |
|---|---|---|
| B1 | Day-truncated comparisons / `inDays` | ⚠️ **Confirmed bug, but not for the checklist's reason** → [BUG-03](#bug-03). Every call site in `updateStreak` **is** correctly day-truncated, so the checklist's 23-hour raw-timestamp case does not apply there. The truncation is nonetheless **insufficient**: two consecutive *local midnights* are 23 hours apart across DST spring-forward, so `inDays == 0` anyway (verified on this machine: `Mar 9→10 2025 = 23h → inDays 0`). **Exception:** `home_screen.dart:74` (`thisWeek`) compares a raw un-truncated `DateTime.now()` against raw stored timestamps — that one *is* the checklist's original case → [BUG-18](#bug-18). |
| B2 | DST / timezone changes | ✅ **Confirmed** → [BUG-03](#bug-03). Spring-forward breaks the streak (23h → `inDays 0`); fall-back survives by luck (25h → `inDays 1`). Timezone travel: eastward flights can compress two local midnights below 24h and swallow a day. |
| B3 | `markRestDay()` bumping `last_workout_date`; Mon→rest Tue→Wed | ✅ **Confirmed** → [BUG-10](#bug-10). **Traced answer: the streak is 2.** Mon `updateStreak` → streak 1, `last_workout_date = Mon`. Tue `markRestDay` → decrements the allowance and sets **both** `last_rest_day_date` **and** `last_workout_date` to Tue. Wed `updateStreak` → `daysDiff == 1` → streak **2**. So a rest day **bridges** the gap but does **not** itself count as a streak day. That semantic is defensible, but it is nowhere stated, it conflicts with the UI's "day streak" label, and it is implemented by **overloading one key with two meanings** — which is the actual bug and the root enabler of BUG-07 and BUG-09. |
| B4 | Rest day on a day that already has a workout | ✅ **Confirmed** → [BUG-07](#bug-07). The same-day guard checks `_lastRestDayKey` only; there is no check against `_lastWorkoutDateKey`. The token is burned for nothing, with no feedback and no undo. |
| B5 | `markRestDay()` with no streak started | ✅ **Confirmed** → [BUG-10](#bug-10) (sub-finding). On a fresh install `getRestDaysRemaining()` seeds the allowance to 2, so Home renders the button for a user who has never trained. Tapping decrements to 1 and writes `last_workout_date` while `streak_count` stays 0. No `streak_count > 0` guard exists. |
| B6 | Rapid-fire `RestDayMarked` idempotency | ✅ **Confirmed** → [BUG-08](#bug-08). **Verified from the installed bloc source, not from memory**: bloc 8.1.4's default transformer processes events **concurrently** (`bloc.dart:62` + doc comments at 33/52/173), and no `transformer:` is supplied. `markRestDay` is a read-modify-write with `await`s between the guard read and the guard write, so two dispatches interleave → **lost update** (two taps, one decrement). The `// Bug 5` same-day guard protects only *sequential* repeats. |
| B7 | `_initWeekIfNeeded()` `>= 7` boundary | ✅ **Confirmed, with the boundary checked at 6/7/8** → [BUG-22](#bug-22). 6 → no reset (correct); 7 → resets (correct); **8 → resets but re-anchors `week_start` to day 8**, so the window **drifts** whenever the app isn't opened on day 7. The allowance **does** reset correctly rather than carrying over (hard `setInt(…, 2)`, not an increment). |
| B8 | Hardcoded `2` in multiple places | ✅ **Confirmed; all copies checked and they agree** → [BUG-19](#bug-19). Six sites: four in the datasource (27, 83, 98, 105), one UI fallback (`home_screen.dart:137`), one spelled-out English word in onboarding copy (`onboarding_screen.dart:30`). The UI fallback is the worst — it optimistically shows "2 rest days left" before load. |
| B9 | `thisWeek / 5` vs 2 rest days; clamping; divide-by-zero | ⚠️ **Partly not a bug** → [BUG-18](#bug-18). The `5` and the `2` **do agree** (7 − 2 = 5); they are simply unlinked literals. **Divide-by-zero is impossible** — the denominator is the literal `5`. Clamping **is** present and correct (`.clamp(0.0, 1.0)`, verified `(0/5).clamp(0.0,1.0) == 0.0`). The **real** defect is that `thisWeek` counts a rolling 168-hour window from `now`, not a calendar week — giving the app a third incompatible definition of "week". |
| B10 | "Best Streak" vs `StreakBloc.currentStreak` | ✅ **Confirmed** → [BUG-09](#bug-09). Two definitions: the persisted counter treats rest days as bridging; the client-side recomputation sees only the `workouts` table and cannot see rest days at all (they live in `SharedPreferences`). They diverge by exactly the number of rest days taken, so **Best can render smaller than Current** — visibly impossible. Reconciliation proposed; it needs rest days as queryable rows, which is a schema change and overlaps Phase 3. **I want your decision on scope here.** |

### C — BLoC lifecycle & async safety

| # | Item | Verdict |
|---|---|---|
| C1 | Double subscription / double-speed timer | ✅ **Not a bug — checked all four start/resume paths.** `WorkoutTimerBloc._onStarted` (line 24) and `RestTimerBloc._onStarted` (line 22) both call `_subscription?.cancel()` **before** assigning. `RestTimerBloc._onResumed` delegates to `add(RestTimerStarted(...))`, inheriting that cancel. `WorkoutTimerBloc._onResumed` (line 70) is the one that does **not** cancel first — but it is protected by `if (state is! WorkoutTimerPausedState) return;`, and the subscription was already cancelled by `_onPaused`, so a double-resume returns early. **Correct, but by state guard rather than by cancellation** — fragile if the guard is ever relaxed. Worth a comment, not a fix. Note the router dispatches `WorkoutTimerStarted` on route creation (`router.dart:61`), so the UI's Start button (shown only in `WorkoutTimerInitialState`) is unreachable in practice. |
| C2 | `emit()` after `close()` | ✅ **Not a crash — verified against the bloc source.** `_Emitter.call` (`emitter.dart:112-136`) guards with `assert(!_isCompleted, …)` — **debug-only, compiled out in release** — and then `if (!_isCanceled) _emit(state);`, so an emit after cancellation is **silently dropped**, not thrown. The `StateError('Cannot emit new states after calling close')` at `bloc_base.dart:96` applies to `BlocBase.emit`, which event handlers do not use. Additionally `bloc.dart:202` guards the internal `onEmit` with `if (isClosed) return;`. **The specific rest-timer case in the checklist is already handled**: `active_screen.dart:264` wraps the `whenComplete` dispatch in `if (!bloc.isClosed)`. |
| C3 | `setState()` after `dispose()` | ✅ **Confirmed — one instance** → [BUG-16](#bug-16). I audited every post-`await` state touch. `onboarding_screen.dart:54` is the **only** unguarded one. `_complete()` (line 69), and both post-frame callbacks in `active_screen.dart` (246, 652-656) are all correctly guarded. |
| C4 | `StreakLoaded()` in `didChangeDependencies` | ⚠️ **Confirmed as a smell, but the checklist overstates the trigger** → [BUG-14](#bug-14). It does **not** fire on keyboard open/close for this widget: an element only depends on inherited widgets it subscribed to via its **own** context, and `_HomeScreenState.build` calls only `Theme.of(context)` — `MediaQuery.of` is never called with Home's context, and `context.read` deliberately does not subscribe. So it fires on **theme changes**, not on every dependency change. It is still the wrong hook, and there **is** a real, unconditional duplicate: the router already dispatches `StreakLoaded` at `router.dart:43`, so the bloc loads **twice on every cold start**. |
| C5 | Timer subscriptions cancelled in `close()` on all paths | ✅ **Not a bug.** Both blocs override `close()` and call `_subscription?.cancel()` before `super.close()` (`workout_timer_bloc.dart:83-87`, `rest_timer_bloc.dart:72-76`). `Stream.periodic(...).take(n)` also terminates on its own. Error paths: neither handler body can throw between the cancel and the reassignment (the only statements are `emit` and a stream construction), so there is no path that abandons a live subscription. `flutter_bloc`'s `BlocProvider` calls `close()` on element unmount, so the route pop is covered. |

### D — Routing & rebuild behaviour

| # | Item | Verdict |
|---|---|---|
| D1 | `key: UniqueKey()` on `/history` | ✅ **Confirmed, mechanism traced through the resolved source** → [BUG-13](#bug-13). The key is constructed **inside** the builder closure, and go_router **13.2.5** invokes that builder from `RouteBuilder._buildPageForGoRoute` (`builder.dart:239-250`), reached from `GoRouterDelegate.build` (`delegate.dart:174-180`) — i.e. on **every rebuild of the `Router` widget**, not just on navigation. A never-equal key fails `Widget.canUpdate`, forcing unmount → `initState` → a fresh N+1 `GetWorkouts` query. (Note: `pubspec.yaml` says `^13.2.0`; the lockfile resolves **13.2.5**.) |
| D2 | Redirect guard: live read or stale capture? | ✅ **NOT A BUG — the checklist's concern does not apply.** `router.dart:27` performs a **live read inside the redirect callback**: `sl<SharedPreferences>().getBool('onboarding_complete') ?? false`. It is re-evaluated on every navigation, so it is never stale. The captured boolean (`createRouter(onboardingComplete)`) is used **only** for `initialLocation` (line 25), which is evaluated once at startup — the correct use for a captured value. After `_complete()` writes the pref and calls `context.go('/')`, the redirect re-reads and correctly allows it. *Minor gap, not the one asked about:* there is no reverse guard stopping a **completed** user from navigating to `/onboarding`. |
| D3 | Back-gesture out of `/active` mid-workout | ✅ **Confirmed** → [BUG-17](#bug-17). No `PopScope`, no `canPop: false`. The in-progress state lives only in a route-scoped `WorkoutBloc` that `BlocProvider` closes on unmount. All the care in `_FinishButton`'s two-step confirm is bypassed by the system back gesture. |

### E — Error handling & observability

| # | Item | Verdict |
|---|---|---|
| E1 | `snapshot.data ?? []` masks DB errors | ✅ **Confirmed at all three sites** → [BUG-11](#bug-11). `hasError` appears **nowhere** in the codebase. **Additional finding:** Home also lacks a `ConnectionState.waiting` branch (History and Calendar have one), so it flashes the "No workouts yet" empty state on every load. **Logging: confirmed absent entirely** — no `dart:developer`, no logging package, no `BlocObserver`, no `FlutterError.onError`. |
| E2 | `WorkoutErrorState` — partial write on transaction failure | ✅ **NOT A BUG — nothing is left behind.** The whole save runs inside `db.transaction((txn) async {...})` (`workout_local_datasource.dart:20-53`), and **all** inserts — the workout row and every exercise and set — use the transaction handle `txn`, with no stray `db.insert` escaping it. sqflite issues `ROLLBACK` when the callback throws, so a mid-transaction failure leaves the database exactly as it was. I verified the failure path concretely with BUG-02's NaN case: the insert throws, the transaction rolls back, and no partial workout row remains. **The real defect on this path is different and is filed as BUG-02**: the error state carries the poisoned `exercises` list forward unchanged (`workout_bloc.dart:86-88`), so every retry re-submits the same bad data and fails identically — the workout becomes permanently unsaveable. Also note `_onHistoryRequested` (line 92-98) has **no** `try/catch`, unlike `_onFinished` — currently harmless only because nothing dispatches that event (BUG-24c). |

### F — Platform reality check

| # | Item | Verdict |
|---|---|---|
| F1 | Web / desktop sqflite support | ✅ **Confirmed** → [BUG-20](#bug-20). The resolved lockfile contains **only** `sqflite_android` and `sqflite_darwin` — no `sqflite_common_ffi`, no `sqflite_common_ffi_web`, and no `databaseFactory` override anywhere in `lib/`. **`flutter run -d chrome`**: the app builds and launches, onboarding works (SharedPreferences has a web implementation), then every DB call throws `MissingPluginException` — which BUG-11 renders as "No workouts yet". **Windows and Linux: same failure.** **macOS: works** — `sqflite_darwin` covers it, so the checklist's grouping of macOS with the broken desktop platforms is incorrect. |
| F2 | google_fonts offline on cold first launch | ✅ **Confirmed — the offline-first claim fails** → [BUG-21](#bug-21). Verified against `google_fonts 6.3.3` source: the loader tries bundled assets → device file cache → **HTTP fetch** (`google_fonts_base.dart:150-184`). `pubspec.yaml` declares **no `fonts:` and no `assets:` section**, so step 1 always misses; step 2 is empty on first launch; step 3 needs network. On failure the exception is caught and reduced to a `print` (line 185-190), so the app does **not** crash — it silently falls back to the platform default font. Subsequent launches are fine once the font is cached to disk. |

### G — Dead code & inconsistency

| # | Item | Verdict |
|---|---|---|
| G1 | Four orphaned widgets | ✅ **Confirmed, zero references each** → [BUG-24a](#bug-24). `streak_badge.dart`, `streak_card.dart`, `timer_display.dart`, `exercise_card.dart`. **Not deleted — awaiting your confirmation.** |
| G2 | Unused JSON codec | ✅ **Confirmed unused** (`dart:convert` never imported) → [BUG-24b](#bug-24). **I argue against deleting this one** — it is complete, correct, and exactly what the Phase-3 export/import candidate needs. |
| G3 | `HistoryRequested` / `WorkoutHistoryState` | ✅ **Confirmed: handler registered, event never dispatched** → [BUG-24c](#bug-24). **I argue against deleting** — this is the intended fix for BUG-13. It needs a `try/catch` before it is wired up. |
| G4 | Unused `flutter_animate` | ✅ **Confirmed** — declared, resolved to 4.5.2, never imported → [BUG-24d](#bug-24). **Recommend removing from `pubspec.yaml`.** |
| G5 | Calendar legend promises unrendered rest-day markers | ✅ **Confirmed** → [BUG-24e](#bug-24). `markerBuilder` only draws workout days; the screen never reads rest-day data at all. **This is closer to a wrong-data bug than to dead code** — the user is told to look for something that cannot appear. |
| G6 | Three near-duplicate date formatters | ✅ **Confirmed — and there are three duplicate *duration* formatters too**, which the checklist missed → [BUG-24f](#bug-24). The three duration formatters are **byte-identical** and all share an unreported bug: `mm:ss` with no hour rollover, so a 90-minute workout renders as `90:00`. All six are hardcoded English with no `intl`. |

---

## 4. Recommended fix order

Sequenced by risk-reduction per unit of change, not strictly by severity — with the dependencies
between findings respected.

**Stage 1 — stop active data loss (small, self-contained, high value)**
1. **BUG-02 + BUG-23** — input validation. One commit; smallest possible change that stops
   unrecoverable workout loss. *Do this first even though BUG-01 is also Critical* — it is a
   ten-line fix against an hour-of-training loss.
2. **BUG-12** — single-flight database getter. Small, isolated, and protects the FK invariant.
3. **BUG-05** — move the pragma to `onConfigure`. Two lines; prerequisite for trustworthy migrations.

**Stage 2 — make the schema changeable (gates everything else)**
4. **BUG-04** — `onUpgrade` scaffold. No user-visible change, but nothing schema-related can land
   before it.

**Stage 3 — the streak cluster (needs the injectable-clock refactor first)**
5. **Refactor commit (separate, per your rules):** inject a clock and `SharedPreferences` into
   `StreakLocalDatasourceImpl` so the logic becomes testable. This is a prerequisite, not a bug fix,
   and gets its own commit with no behaviour change.
6. **BUG-03** — civil-date arithmetic, with the full unit-test suite you specified (consecutive days,
   gap of exactly 1, gap > 1, same-day double, rest-then-workout, week rollover at 6/7/8, DST pair).
7. **BUG-07 + BUG-10** — one reasoned commit; they are the same defect (one key, two meanings).
8. **BUG-08** — event serialisation. **Pending your decision on `bloc_concurrency`.**
9. **BUG-18 + BUG-19 + BUG-22** — define "the week" and the allowance in one place.

**Stage 4 — correctness of what's displayed**
10. **BUG-06** — capture `startedAt`.
11. **BUG-11** — error states + a minimal `BlocObserver`.
12. **BUG-01** — canonical kg + display-boundary conversion. Largest blast radius; rides on BUG-04's
    migration. **Pending your decision on treating existing rows as kg.**

**Stage 5 — UX and lifecycle**
13. BUG-13, BUG-14 (decide together — both are about History/Home staleness)
14. BUG-15, BUG-16, BUG-17, BUG-25

**Stage 6 — platform and hygiene**
15. **BUG-20** — pending your product decision (narrow the claim vs. add the implementations).
16. **BUG-21** — bundle fonts.
17. **BUG-24** — deletions, **only after you confirm the list**. Refactors (formatter consolidation)
    in their own separate commits.

**Deferred to Phase 3 (recommended):** BUG-09's full reconciliation — it needs rest days as
queryable rows, which is a feature, not a fix.

---

## 5. Decisions I need from you before Phase 2

I have deliberately not chosen these, because each is genuinely yours:

1. **BUG-01 unit migration** — do we treat all existing `weight` rows as **kg**? Any other choice
   silently rescales real training data. I recommend kg (the app default) and documenting it.
2. **BUG-09 scope** — for Phase 2, do we (a) remove "Best Streak" as knowingly wrong, (b) fix only its
   DST bug and accept the disagreement, or (c) do the full reconciliation now (schema change,
   overlaps Phase 3)? **I recommend (a) or (b)**, deferring the reconciliation.
3. **BUG-08 new dependency** — may I add `bloc_concurrency` (official bloc package) for
   `sequential()`? The alternative I'd otherwise use is a hand-rolled busy-latch in the bloc, which is
   the same idea with more failure modes. Your call per the no-new-dependencies rule.
4. **BUG-20 platform scope** — narrow the README to Android/iOS/macOS, or add `sqflite_common_ffi`
   (+ `_web`)? Note that adding `sqflite_common_ffi` **as a dev_dependency only** would let us write
   real datasource tests, which is a meaningful testability win independent of shipping desktop.
5. **BUG-24 deletions** — confirm the four orphaned widgets and `flutter_animate` may go. I recommend
   **keeping** the JSON codec and `HistoryRequested`/`WorkoutHistoryState`, and argue for that in
   BUG-24b/c.
6. **BUG-04 downgrade policy** — is wiping the database on an app *downgrade*
   (`onDatabaseDowngradeDelete`) acceptable? The alternative is an unlaunchable app.

---

## 6. Verification method

Every mechanical claim in this report was checked against the actual source or an executed probe.
Nothing here is recalled from memory about how a package "usually" behaves.

- **Dart date/parse semantics** — executed probes: DST spring-forward on truncated dates
  (`23h → inDays 0`), fall-back (`25h → inDays 1`), the 23:30→00:30 case, `double.tryParse` on
  `NaN`/`Infinity`/`1e309`/negatives, `toStringAsFixed` on non-finite values, and `clamp` behaviour.
- **SQLite semantics** — executed against `sqlite3`: `PRAGMA foreign_keys` inside vs. outside a
  transaction (`fk=0` vs `fk=1`); `INSERT OR REPLACE` cascade behaviour with FK ON (children `1→0`)
  and OFF (children survive); NaN insertion into a `REAL NOT NULL` column
  (`NOT NULL constraint failed`); Infinity stored as REAL `Inf`.
- **bloc 8.1.4** — read `bloc.dart` (default transformer, `isClosed` guard at line 202) and
  `emitter.dart` (`assert` vs silent drop at lines 112-136).
- **go_router 13.2.5** — traced `delegate.build` → `RouteBuilder._buildPageForGoRoute` → `route.builder`.
- **google_fonts 6.3.3** — read the three-tier loader and the swallowing `catch`.
- **Dependency versions** — read from `pubspec.lock`, not `pubspec.yaml` (they differ for go_router).
- **Dead-code claims** — `grep` across `lib/` for every symbol, excluding its own definition file.
- **Analyzer** — `flutter analyze` → *No issues found!* before any change.

**No code has been modified.** `git status` shows only the pre-existing `README.md` modification,
plus this new file.
