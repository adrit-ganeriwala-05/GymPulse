import '../../domain/exercise_name.dart';
import '../../domain/read_models/exercise_progress.dart';
import '../../domain/repositories/progress_repository.dart';
import '../datasources/progress_local_datasource.dart';

class ProgressRepositoryImpl implements ProgressRepository {
  final ProgressLocalDatasource datasource;

  const ProgressRepositoryImpl(this.datasource);

  @override
  Future<ExerciseProgress> getExerciseProgress(String name) async {
    final key = normalizeExerciseName(name);
    final rows = await datasource.topSetPerWorkout(key);
    final displayName = await datasource.latestDisplayName(key) ?? name.trim();
    return ExerciseProgress.fromWorkoutTopSets(
      key: key,
      displayName: displayName,
      perWorkout: rows.map((r) => (
            // Stored as local ISO without offset; parse gives local time and
            // the domain fold applies civilDate — no arithmetic here.
            date: DateTime.parse(r.date),
            reps: r.reps,
            weightKg: r.weight,
          )),
    );
  }
}
