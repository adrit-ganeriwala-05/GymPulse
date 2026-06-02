import '../../domain/entities/exercise.dart';

class ExerciseSetModel extends ExerciseSet {
  const ExerciseSetModel({required super.reps, required super.weight});

  factory ExerciseSetModel.fromJson(Map<String, dynamic> json) =>
      ExerciseSetModel(
        reps: json['reps'] as int,
        weight: (json['weight'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'reps': reps, 'weight': weight};

  factory ExerciseSetModel.fromEntity(ExerciseSet set) =>
      ExerciseSetModel(reps: set.reps, weight: set.weight);
}

class ExerciseModel extends Exercise {
  final List<ExerciseSetModel> modelSets;

  ExerciseModel({required super.name, required this.modelSets})
      : super(sets: modelSets);

  factory ExerciseModel.fromJson(Map<String, dynamic> json) => ExerciseModel(
        name: json['name'] as String,
        modelSets: (json['sets'] as List<dynamic>)
            .map((s) => ExerciseSetModel.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'sets': modelSets.map((s) => s.toJson()).toList(),
      };

  factory ExerciseModel.fromEntity(Exercise exercise) => ExerciseModel(
        name: exercise.name,
        modelSets:
            exercise.sets.map(ExerciseSetModel.fromEntity).toList(),
      );
}
