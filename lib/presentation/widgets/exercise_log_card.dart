import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/entities/exercise.dart';

class ExerciseLogCard extends StatefulWidget {
  final Exercise exercise;
  final void Function(int reps, double weight) onAddSet;
  final void Function(int setIndex) onRemoveSet;
  final VoidCallback onRemoveExercise;
  // FIX: weightUnit param so sets display the user's chosen unit (kg or lbs)
  final String weightUnit;

  const ExerciseLogCard({
    super.key,
    required this.exercise,
    required this.onAddSet,
    required this.onRemoveSet,
    required this.onRemoveExercise,
    this.weightUnit = 'kg',
  });

  /// Upper bounds are generous sanity caps, not domain rules: they exist to
  /// keep a fat-fingered "1000000" out of the database.
  static const maxReps = 1000;
  static const maxWeight = 2000.0;

  @override
  State<ExerciseLogCard> createState() => _ExerciseLogCardState();
}

class _ExerciseLogCardState extends State<ExerciseLogCard> {
  bool _expanded = true;
  bool _addingSet = false;
  final _repsCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  String? _repsError;
  String? _weightError;

  @override
  void dispose() {
    _repsCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  void _submitSet() {
    final reps = int.tryParse(_repsCtrl.text.trim());
    final weight = double.tryParse(_weightCtrl.text.trim());

    // Validate domain meaning, not just parse success. `isFinite` rejects
    // NaN and ±Infinity, which SQLite cannot round-trip (NaN becomes NULL and
    // violates the NOT NULL constraint, making the workout unsaveable).
    String? repsError;
    String? weightError;
    if (reps == null) {
      repsError = 'Enter a number';
    } else if (reps <= 0) {
      repsError = 'Must be > 0';
    } else if (reps > ExerciseLogCard.maxReps) {
      repsError = 'Max ${ExerciseLogCard.maxReps}';
    }
    if (weight == null || !weight.isFinite) {
      weightError = 'Enter a number';
    } else if (weight < 0) {
      weightError = 'Cannot be negative';
    } else if (weight > ExerciseLogCard.maxWeight) {
      weightError = 'Max ${ExerciseLogCard.maxWeight.toInt()}';
    }
    if (repsError != null || weightError != null) {
      setState(() {
        _repsError = repsError;
        _weightError = weightError;
      });
      return;
    }

    widget.onAddSet(reps!, weight!);
    _repsCtrl.clear();
    _weightCtrl.clear();
    setState(() {
      _addingSet = false;
      _repsError = null;
      _weightError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            onTap: () => setState(() => _expanded = !_expanded),
            title: Text(
              widget.exercise.name,
              style: GoogleFonts.dmSans(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Remove exercise',
                  icon: Icon(Icons.delete_outline, color: cs.outline, size: 20),
                  onPressed: widget.onRemoveExercise,
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: cs.outline,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...widget.exercise.sets.asMap().entries.map(
                        (e) => Row(
                          children: [
                            Expanded(
                              child: Text(
                                // FIX: use weightUnit instead of hardcoded 'kg'
                                'Set ${e.key + 1}  ${e.value.reps} reps  ×  ${e.value.weight} ${widget.weightUnit}',
                                style: GoogleFonts.dmSans(
                                  color: const Color(0xFF4A3728),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove set',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.close, size: 16, color: cs.outline),
                              onPressed: () => widget.onRemoveSet(e.key),
                            ),
                          ],
                        ),
                      ),
                  if (_addingSet) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _repsCtrl,
                            keyboardType: TextInputType.number,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: 'Reps',
                              isDense: true,
                              errorText: _repsError,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _weightCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              // FIX: weight field label shows chosen unit
                              labelText: widget.weightUnit,
                              isDense: true,
                              errorText: _weightError,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _submitSet,
                          icon: Icon(Icons.check_circle, color: cs.primary),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => setState(() => _addingSet = !_addingSet),
                    icon: Icon(
                      _addingSet ? Icons.close : Icons.add,
                      size: 16,
                      color: cs.primary,
                    ),
                    label: Text(
                      _addingSet ? 'Cancel' : 'Log Set',
                      style: TextStyle(color: cs.primary),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
