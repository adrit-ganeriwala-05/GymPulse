class ExerciseSet {
  final int reps;
  final double weight;

  const ExerciseSet({required this.reps, required this.weight});
}

class Exercise {
  final String name;
  final List<ExerciseSet> sets;

  const Exercise({required this.name, required this.sets});
}
