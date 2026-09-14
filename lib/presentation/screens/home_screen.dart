import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/entities/workout.dart';
import '../../domain/streak_rules.dart';
import '../../domain/usecases/get_workouts.dart';
import '../../injection_container.dart';
import '../blocs/streak/streak_bloc.dart';
import '../blocs/streak/streak_event.dart';
import '../blocs/streak/streak_state.dart';
import '../format.dart';
import '../widgets/load_error_view.dart';
import '../widgets/workout_summary_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _userName = 'Athlete';
  late Future<List<Workout>> _workoutsFuture;

  // One-shot loads belong in initState. StreakLoaded is dispatched by the
  // route's BlocProvider (router.dart), not here — one owner (BUG-14).
  @override
  void initState() {
    super.initState();
    _userName = sl<SharedPreferences>().getString('user_name') ?? 'Athlete';
    _workoutsFuture = sl<GetWorkouts>().call();
  }

  void _reload() => setState(() => _workoutsFuture = sl<GetWorkouts>().call());

  // FIX: greeting changed from time-of-day to "Welcome, name 👋" per spec
  String _greeting() => 'Welcome, $_userName 👋';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GymPulse'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.calendar_month, color: cs.primary),
            onPressed: () => context.push('/calendar'),
          ),
        ],
      ),
      body: FutureBuilder<List<Workout>>(
        future: _workoutsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: cs.primary));
          }
          if (snapshot.hasError) return LoadErrorView(onRetry: _reload);
          final workouts = snapshot.data ?? const <Workout>[];
          final now = DateTime.now();

          final thisMonth = workouts
              .where((w) => w.date.month == now.month && w.date.year == now.year)
              .length;
          // Calendar week (Mon-Sun), same definition the rest-day allowance uses.
          final weekStart = startOfWeek(now);
          final thisWeek = workouts
              .map((w) => civilDate(w.date))
              .toSet()
              .where((d) => !d.isBefore(weekStart))
              .length;
          final weekProgress =
              (thisWeek / kTrainingDaysPerWeek).clamp(0.0, 1.0);
          final trainedToday = workouts.any((w) => isSameCivilDay(w.date, now));

          // Longest run of consecutive *workout* days. Deliberately not called
          // a "streak": the streak card counts rest days as bridging, this
          // tile cannot see rest days. Reconciliation is deferred (BUG-09).
          int longestRun = 0;
          int cur = 0;
          DateTime? last;
          final days = workouts.map((w) => civilDate(w.date)).toSet().toList()
            ..sort();
          for (final day in days) {
            cur = (last != null && civilDaysBetween(last, day) == 1) ? cur + 1 : 1;
            if (cur > longestRun) longestRun = cur;
            last = day;
          }

          // Recent Activity should show every workout from the most recent
          // workout day, not just the single newest one. workouts is sorted
          // newest-first, so workouts.first is the latest day.
          final List<Workout> recentDayWorkouts;
          if (workouts.isEmpty) {
            recentDayWorkouts = const [];
          } else {
            final latest = workouts.first.date;
            final latestDay = DateTime(latest.year, latest.month, latest.day);
            recentDayWorkouts = workouts.where((w) {
              final d = DateTime(w.date.year, w.date.month, w.date.day);
              return d == latestDay;
            }).toList();
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      style: Theme.of(context).textTheme.displayMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDayMonth(DateTime.now()),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.primary,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Divider(color: cs.outline),
                  ],
                ),
              ),

              BlocBuilder<StreakBloc, StreakState>(
                builder: (context, state) {
                  final streak = state is StreakLoadedState ? state.currentStreak : 0;
                  final restDays = state is StreakLoadedState ? state.restDaysRemaining : 0;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    const Text('🔥', style: TextStyle(fontSize: 40)),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$streak',
                                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                                            color: const Color(0xFF6B4226),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'current streak',
                                    style: GoogleFonts.dmSans(
                                      fontSize: 12,
                                      color: const Color(0xFF8B7355),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '🌿 $restDays rest days left',
                                    style: GoogleFonts.dmSans(
                                      fontSize: 14,
                                      color: const Color(0xFF4A3728),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: weekProgress,
                              minHeight: 6,
                              backgroundColor: cs.outline,
                              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '$thisWeek / $kTrainingDaysPerWeek days this week',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: const Color(0xFF8B7355),
                              ),
                            ),
                          ),
                          // Datasource enforces this too; hiding the button
                          // just makes the rule discoverable.
                          if (restDays > 0 && streak > 0 && !trainedToday) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => context
                                  .read<StreakBloc>()
                                  .add(const RestDayMarked()),
                              icon: const Icon(
                                Icons.spa_outlined,
                                color: Color(0xFF6B4226),
                                size: 18,
                              ),
                              label: Text(
                                'Mark Rest Day ($restDays left this week)',
                                style: GoogleFonts.dmSans(
                                  color: const Color(0xFF6B4226),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0xFF6B4226),
                                ),
                                minimumSize: const Size(double.infinity, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  _StatCard(label: 'This Month', value: '$thisMonth'),
                  const SizedBox(width: 8),
                  _StatCard(label: 'Longest run', value: '$longestRun'),
                  const SizedBox(width: 8),
                  _StatCard(label: 'This Week', value: '$thisWeek'),
                ],
              ),
              const SizedBox(height: 20),

              SizedBox(
                height: 60,
                child: ElevatedButton(
                  onPressed: () => context.go('/active'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    shadowColor: const Color(0x406B4226),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Begin Workout 💪',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'Recent Activity',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (workouts.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No workouts yet.\nStart your first!',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.dmSans(
                        color: const Color(0xFF8B7355),
                        fontSize: 16,
                      ),
                    ),
                  ),
                )
              else
                ...recentDayWorkouts.map(
                  (w) => GestureDetector(
                    onTap: () => context.push('/history'),
                    child: WorkoutSummaryCard(
                      workout: w,
                      weightUnit:
                          sl<SharedPreferences>().getString('weight_unit') ??
                              'kg',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Text(
                value,
                style: GoogleFonts.playfairDisplay(
                  color: cs.primary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  color: const Color(0xFF4A3728),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
