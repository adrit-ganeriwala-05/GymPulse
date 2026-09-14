import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/entities/workout.dart';
import '../../domain/streak_rules.dart';
import '../../domain/workout_stats.dart';
import '../../domain/usecases/discard_all_drafts.dart';
import '../../domain/usecases/get_draft.dart';
import '../../domain/usecases/get_workouts.dart';
import '../../injection_container.dart';
import '../blocs/streak/streak_bloc.dart';
import '../blocs/streak/streak_event.dart';
import '../blocs/streak/streak_state.dart';
import '../format.dart';
import '../router.dart';
import '../widgets/load_error_view.dart';
import '../widgets/workout_summary_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  String _userName = 'Athlete';
  late Future<List<Workout>> _workoutsFuture;
  Workout? _draft;

  // One-shot loads belong in initState. StreakLoaded is dispatched by the
  // route's BlocProvider (router.dart), not here — one owner (BUG-14).
  @override
  void initState() {
    super.initState();
    _userName = sl<SharedPreferences>().getString('user_name') ?? 'Athlete';
    _workoutsFuture = sl<GetWorkouts>().call();
    _loadDraft();
  }

  void _reload() {
    // Block body: an arrow would return the assignment's Future from the
    // setState callback, which the framework rejects.
    setState(() {
      _workoutsFuture = sl<GetWorkouts>().call();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  /// /active (and /history, /calendar) are pushed above Home, so Home is
  /// not recreated when they finish. Refresh everything that could change.
  @override
  void didPopNext() {
    _reload();
    _loadDraft();
    context.read<StreakBloc>().add(const StreakLoaded());
  }

  Future<void> _loadDraft() async {
    Workout? draft;
    try {
      draft = (await sl<GetDraft>().call())?.workout;
    } catch (_) {
      draft = null; // banner is a convenience; the DB error surfaces below
    }
    if (mounted) setState(() => _draft = draft);
  }

  Future<void> _discardDraft() async {
    final d = _draft;
    if (d == null) return;
    try {
      // Every draft, not just the one shown: a stray second row must not
      // outlive the user's Discard (A2-08).
      await sl<DiscardAllDrafts>().call();
    } catch (_) {
      // Banner stays: the row is still there. Say so instead of throwing
      // out of the tap handler (A2-05).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not discard draft')),
        );
      }
      return;
    }
    if (mounted) setState(() => _draft = null);
  }

  String _ago(DateTime then) {
    // Clamp: a clock set backwards must not render "-30 min ago" (A2-06).
    var d = DateTime.now().difference(then);
    if (d.isNegative) d = Duration.zero;
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  }

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

          final thisMonth = countThisMonth(workouts, now);
          final thisWeek = countThisWeek(workouts, now);
          final weekProgress =
              (thisWeek / kTrainingDaysPerWeek).clamp(0.0, 1.0);
          final longest = longestRun(workouts);
          final recentDayWorkouts = mostRecentDay(workouts);

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
                  final canRest = state is StreakLoadedState && state.canRestToday;
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
                          // One rule, owned by the datasource: the button is
                          // shown iff a tap would succeed (A2-02).
                          if (canRest) ...[
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
                  _StatCard(label: 'Longest run', value: '$longest'),
                  const SizedBox(width: 8),
                  _StatCard(label: 'This Week', value: '$thisWeek'),
                ],
              ),
              const SizedBox(height: 20),

              if (_draft != null) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.pending_actions, color: Color(0xFF6B4226)),
                    title: Text('Workout in progress',
                        style: Theme.of(context).textTheme.titleMedium),
                    subtitle: Text(
                      '${_draft!.exercises.length} exercises · ${formatDuration(_draft!.durationSeconds)} active · started ${_ago(_draft!.date)}',
                      style: GoogleFonts.dmSans(fontSize: 13),
                    ),
                    // Stale drafts are kept, never auto-deleted: the age is
                    // shown and Discard is a real button, so the user decides.
                    trailing: OutlinedButton(
                      onPressed: _discardDraft,
                      child: const Text('Discard'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
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
                    _draft != null ? 'Resume Workout ▶' : 'Begin Workout 💪',
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

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Activity',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  // Explicit link: the card's own InkWell (expand) wins the
                  // gesture arena, so a tap on the card never navigated.
                  if (workouts.isNotEmpty)
                    TextButton(
                      onPressed: () => context.push('/history'),
                      child: const Text('View all'),
                    ),
                ],
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
                  (w) => WorkoutSummaryCard(
                    workout: w,
                    onTap: () => context.push('/history'),
                    weightUnit:
                        sl<SharedPreferences>().getString('weight_unit') ??
                            'kg',
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
