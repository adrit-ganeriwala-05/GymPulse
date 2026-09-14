import '../read_models/exercise_progress.dart';
import '../repositories/progress_repository.dart';

class GetExerciseProgress {
  final ProgressRepository repository;

  const GetExerciseProgress(this.repository);

  Future<ExerciseProgress> call(String name) =>
      repository.getExerciseProgress(name);
}
