// The exercise-name key. Names are free text typed by the user; "Bench",
// "bench" and "Bench " are one exercise. The rule is deliberately minimal —
// trim and case-fold — and lives in domain so the datasource (which stores
// the key), the bloc (which dedupes within a session) and any future caller
// agree by construction. Do not add merge/rename logic here.

/// Canonical key for an exercise name: trimmed, lower-cased (Unicode-aware,
/// via Dart — SQLite's lower() is ASCII-only, which is why the v4 migration
/// backfills the column from Dart rather than in SQL).
String normalizeExerciseName(String name) => name.trim().toLowerCase();
