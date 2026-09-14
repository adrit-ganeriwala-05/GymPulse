import '../../domain/entities/exercise.dart';

class ExerciseSetModel extends ExerciseSet {
  const ExerciseSetModel({required super.reps, required super.weight});

  factory ExerciseSetModel.fromEntity(ExerciseSet set) =>
      ExerciseSetModel(reps: set.reps, weight: set.weight);
}

class ExerciseModel extends Exercise {
  final List<ExerciseSetModel> modelSets;

  ExerciseModel({required super.name, required this.modelSets})
      : super(sets: modelSets);

  factory ExerciseModel.fromEntity(Exercise exercise) => ExerciseModel(
        name: exercise.name,
        modelSets: exercise.sets.map(ExerciseSetModel.fromEntity).toList(),
      );
}
