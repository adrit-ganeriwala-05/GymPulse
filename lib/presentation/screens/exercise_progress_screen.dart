import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/read_models/exercise_progress.dart';
import '../../domain/usecases/get_exercise_progress.dart';
import '../../injection_container.dart';
import '../format.dart';
import '../units.dart';
import '../widgets/load_error_view.dart';

/// Feature D: one exercise's top set per training day and its PR. Fetched
/// once on mount (FutureBuilder, the same shape as History and Calendar); the
/// live "new PR" badge on save is deferred until a reactive read path exists.
class ExerciseProgressScreen extends StatefulWidget {
  final String name;

  const ExerciseProgressScreen({super.key, required this.name});

  @override
  State<ExerciseProgressScreen> createState() => _ExerciseProgressScreenState();
}

class _ExerciseProgressScreenState extends State<ExerciseProgressScreen> {
  late Future<ExerciseProgress> _future;

  @override
  void initState() {
    super.initState();
    _future = sl<GetExerciseProgress>().call(widget.name);
  }

  void _reload() {
    // Block body: an arrow would return the assignment's Future from the
    // setState callback, which the framework rejects.
    setState(() {
      _future = sl<GetExerciseProgress>().call(widget.name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unit = sl<SharedPreferences>().getString('weight_unit') ?? 'kg';
    return FutureBuilder<ExerciseProgress>(
      future: _future,
      builder: (context, snapshot) {
        final progress = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(progress?.displayName ?? widget.name.trim()),
            elevation: 0,
          ),
          body: switch (snapshot.connectionState) {
            ConnectionState.waiting =>
              Center(child: CircularProgressIndicator(color: cs.primary)),
            _ when snapshot.hasError => LoadErrorView(onRetry: _reload),
            _ when progress == null || progress.isEmpty => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No finished workouts include this exercise yet.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      color: const Color(0xFF8B7355),
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            _ => _ProgressBody(progress: progress, unit: unit),
          },
        );
      },
    );
  }
}

class _ProgressBody extends StatelessWidget {
  final ExerciseProgress progress;
  final String unit;

  const _ProgressBody({required this.progress, required this.unit});

  String _set(ExerciseTopSet s) =>
      '${formatWeight(s.weightKg, unit)} $unit × ${s.reps}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pr = progress.pr!;
    final days = progress.days;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Personal record',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: const Color(0xFF8B7355),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _set(pr),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: cs.primary,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatDayMonth(pr.day, shortDay: true)} · '
                  '${days.length} training day${days.length == 1 ? '' : 's'}',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: const Color(0xFF4A3728),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Top set per day', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        // Newest first: the log is read from the top.
        for (var i = days.length - 1; i >= 0; i--)
          _DayRow(
            set: days[i],
            label: _set(days[i]),
            fraction: pr.weightKg == 0 ? 1 : days[i].weightKg / pr.weightKg,
            badge: progress.isPr(i)
                ? 'PR'
                : progress.matchesPr(i)
                    ? '= PR'
                    : null,
          ),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  final ExerciseTopSet set;
  final String label;
  final double fraction;
  final String? badge;

  const _DayRow({
    required this.set,
    required this.label,
    required this.fraction,
    required this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              formatDayMonth(set.day, shortDay: true),
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: const Color(0xFF4A3728),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: FractionallySizedBox(
                    widthFactor: fraction.clamp(0.05, 1.0),
                    child: Container(height: 22, color: cs.tertiaryContainer),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    label,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badge == 'PR' ? cs.primary : cs.surface,
                border: Border.all(color: cs.primary),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge!,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: badge == 'PR' ? Colors.white : cs.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
