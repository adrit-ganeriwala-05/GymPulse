import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/entities/workout.dart';
import '../../domain/workout_stats.dart';
import '../format.dart';
import '../units.dart';

class WorkoutSummaryCard extends StatefulWidget {
  final Workout workout;
  // FIX: weightUnit param so history/home shows kg or lbs consistently
  final String weightUnit;

  /// When set, a tap navigates instead of expanding. Threaded into the
  /// card's own InkWell: wrapping a tappable widget in an outer
  /// GestureDetector loses the gesture arena to the inner InkWell.
  final VoidCallback? onTap;

  /// When set, an exercise name in the expanded card is tappable (History →
  /// exercise progress, Feature D).
  final void Function(String name)? onExerciseTap;

  const WorkoutSummaryCard({
    super.key,
    required this.workout,
    this.weightUnit = 'kg',
    this.onTap,
    this.onExerciseTap,
  });

  @override
  State<WorkoutSummaryCard> createState() => _WorkoutSummaryCardState();
}

class _WorkoutSummaryCardState extends State<WorkoutSummaryCard> {
  bool _expanded = false;

  double get _totalVolume => totalVolumeKg(widget.workout);

  int get _totalSets => widget.workout.exercises.fold(0, (sum, e) => sum + e.sets.length);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: widget.onTap ?? () => setState(() => _expanded = !_expanded),
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
                          formatDayMonth(widget.workout.date, shortDay: true),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: cs.primary,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          children: [
                            _chip('⏱ ${formatDuration(widget.workout.durationSeconds)}'),
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
                          InkWell(
                            onTap: widget.onExerciseTap == null
                                ? null
                                : () => widget.onExerciseTap!(exercise.name),
                            borderRadius: BorderRadius.circular(6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  exercise.name,
                                  style: GoogleFonts.dmSans(
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary,
                                    fontSize: 15,
                                  ),
                                ),
                                if (widget.onExerciseTap != null)
                                  Icon(Icons.chevron_right,
                                      size: 18, color: cs.primary),
                              ],
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
