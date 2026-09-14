class ExerciseSet {
  final int reps;

  /// Always kilograms. The kg/lbs preference is a display concern; conversion
  /// happens at the presentation boundary (see presentation/units.dart).
  final double weight;

  const ExerciseSet({required this.reps, required this.weight});
}

class Exercise {
  final String name;
  final List<ExerciseSet> sets;

  const Exercise({required this.name, required this.sets});
}
