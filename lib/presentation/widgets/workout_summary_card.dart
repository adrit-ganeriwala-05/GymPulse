import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/entities/workout.dart';
import '../units.dart';

class WorkoutSummaryCard extends StatefulWidget {
  final Workout workout;
  // FIX: weightUnit param so history/home shows kg or lbs consistently
  final String weightUnit;

  const WorkoutSummaryCard({
    super.key,
    required this.workout,
    this.weightUnit = 'kg',
  });

  @override
  State<WorkoutSummaryCard> createState() => _WorkoutSummaryCardState();
}

class _WorkoutSummaryCardState extends State<WorkoutSummaryCard> {
  bool _expanded = false;

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  double get _totalVolume => widget.workout.exercises.fold(0.0, (sum, e) {
        return sum + e.sets.fold(0.0, (s, set) => s + set.reps * set.weight);
      });

  int get _totalSets => widget.workout.exercises.fold(0, (sum, e) => sum + e.sets.length);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDate(widget.workout.date),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: cs.primary,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          children: [
                            _chip('⏱ ${_formatDuration(widget.workout.durationSeconds)}'),
                            _chip('🏋 ${widget.workout.exercises.length} exercises'),
                            // FIX: show unit next to volume
                            _chip('📦 ${formatWeight(_totalVolume, widget.weightUnit, decimals: 0)} ${widget.weightUnit}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.outline,
                  ),
                ],
              ),
              if (_expanded && widget.workout.exercises.isNotEmpty) ...[
                const SizedBox(height: 12),
                Divider(color: cs.outline.withValues(alpha: 0.5)),
                ...widget.workout.exercises.map((exercise) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exercise.name,
                            style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...exercise.sets.asMap().entries.map((e) => Text(
                                // FIX: use weightUnit not hardcoded 'kg'
                                'Set ${e.key + 1}: ${e.value.reps} reps × ${formatWeight(e.value.weight, widget.weightUnit)} ${widget.weightUnit}',
                                style: GoogleFonts.dmSans(
                                  color: const Color(0xFF4A3728),
                                  fontSize: 14,
                                ),
                              )),
                        ],
                      ),
                    )),
                const SizedBox(height: 8),
                Text(
                  '${widget.workout.exercises.length} exercises · $_totalSets sets · ${formatWeight(_totalVolume, widget.weightUnit, decimals: 0)} ${widget.weightUnit} total volume',
                  style: GoogleFonts.dmSans(
                    color: const Color(0xFF8B7355),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text) => Text(
        text,
        style: GoogleFonts.dmSans(color: const Color(0xFF4A3728), fontSize: 13),
      );
}
