import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/entities/exercise.dart';

class ExerciseLogCard extends StatefulWidget {
  final Exercise exercise;
  final void Function(int reps, double weight) onAddSet;
  // FIX: weightUnit param so sets display the user's chosen unit (kg or lbs)
  final String weightUnit;

  const ExerciseLogCard({
    super.key,
    required this.exercise,
    required this.onAddSet,
    this.weightUnit = 'kg',
  });

  @override
  State<ExerciseLogCard> createState() => _ExerciseLogCardState();
}

class _ExerciseLogCardState extends State<ExerciseLogCard> {
  bool _expanded = true;
  bool _addingSet = false;
  final _repsCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  @override
  void dispose() {
    _repsCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  void _submitSet() {
    final reps = int.tryParse(_repsCtrl.text.trim());
    final weight = double.tryParse(_weightCtrl.text.trim());
    if (reps == null || weight == null) return;
    widget.onAddSet(reps, weight);
    _repsCtrl.clear();
    _weightCtrl.clear();
    setState(() => _addingSet = false);
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
            trailing: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              color: cs.outline,
            ),
          ),
          if (_expanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...widget.exercise.sets.asMap().entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            // FIX: use weightUnit instead of hardcoded 'kg'
                            'Set ${e.key + 1}  ${e.value.reps} reps  ×  ${e.value.weight} ${widget.weightUnit}',
                            style: GoogleFonts.dmSans(
                              color: const Color(0xFF4A3728),
                              fontSize: 14,
                            ),
                          ),
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
                            decoration: const InputDecoration(
                              labelText: 'Reps',
                              isDense: true,
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
