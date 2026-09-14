import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/workout.dart';
import '../../domain/usecases/get_workouts.dart';
import '../../injection_container.dart';
import '../widgets/load_error_view.dart';
import '../widgets/workout_summary_card.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<Workout>> _workoutsFuture;

  @override
  void initState() {
    super.initState();
    _workoutsFuture = sl<GetWorkouts>().call();
  }

  void _reload() => setState(() => _workoutsFuture = sl<GetWorkouts>().call());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout History'),
        elevation: 0,
      ),
      body: FutureBuilder<List<Workout>>(
        future: _workoutsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: cs.primary),
            );
          }

          if (snapshot.hasError) return LoadErrorView(onRetry: _reload);
          final workouts = snapshot.data ?? const <Workout>[];

          if (workouts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🏋️', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 16),
                  Text(
                    'No workouts yet',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Begin your fitness journey',
                    style: GoogleFonts.dmSans(
                      color: const Color(0xFF8B7355),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: ElevatedButton(
                      onPressed: () => context.go('/active'),
                      child: Text(
                        'Start Workout',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // Datasource already returns workouts newest-first (ORDER BY date
          // DESC). Render in that order; reversing it showed oldest first.
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: workouts.length,
            itemBuilder: (context, index) => WorkoutSummaryCard(
              workout: workouts[index],
              // FIX: pass saved unit so history shows kg or lbs correctly
              weightUnit: sl<SharedPreferences>().getString('weight_unit') ?? 'kg',
            ),
          );
        },
      ),
    );
  }
}
