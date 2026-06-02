import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/entities/exercise.dart';

class ExerciseCard extends StatelessWidget {
  final Exercise exercise;

  const ExerciseCard({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exercise.name,
            style: GoogleFonts.dmSans(
              color: cs.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (exercise.sets.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _headerCell(context, 'Set'),
                _headerCell(context, 'Reps'),
                _headerCell(context, 'Weight (kg)'),
              ],
            ),
            Divider(color: cs.outline, height: 8),
            ...exercise.sets.asMap().entries.map((entry) {
              final i = entry.key;
              final set = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    _cell(context, '${i + 1}'),
                    _cell(context, '${set.reps}'),
                    _cell(context, '${set.weight}'),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _headerCell(BuildContext context, String text) => Expanded(
        child: Text(
          text,
          style: GoogleFonts.dmSans(
            color: const Color(0xFF8B7355),
            fontSize: 12,
          ),
        ),
      );

  Widget _cell(BuildContext context, String text) => Expanded(
        child: Text(
          text,
          style: GoogleFonts.dmSans(
            color: const Color(0xFF4A3728),
            fontSize: 14,
          ),
        ),
      );
}
