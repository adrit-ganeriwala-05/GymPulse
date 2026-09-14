import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../domain/entities/workout.dart';
import '../../domain/usecases/get_workouts.dart';
import '../../injection_container.dart';
import '../units.dart';
import '../widgets/load_error_view.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late Future<List<Workout>> _workoutsFuture;

  @override
  void initState() {
    super.initState();
    _workoutsFuture = sl<GetWorkouts>().call();
  }

  void _reload() => setState(() => _workoutsFuture = sl<GetWorkouts>().call());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF6B4226),
          ),
          // FIX: pop() not go('/') — preserves navigation stack correctly
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Streak Calendar',
          style: GoogleFonts.playfairDisplay(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1C0F08),
          ),
        ),
        backgroundColor: const Color(0xFFFDF8F3),
        elevation: 0,
        centerTitle: true,
      ),
      body: FutureBuilder<List<Workout>>(
        future: _workoutsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return LoadErrorView(onRetry: _reload);
          final workouts = snapshot.data ?? const <Workout>[];
          final workoutsByDay = <DateTime, List<Workout>>{};
          for (final w in workouts) {
            final key = DateTime(w.date.year, w.date.month, w.date.day);
            workoutsByDay.putIfAbsent(key, () => []).add(w);
          }
          return _CalendarView(workoutsByDay: workoutsByDay);
        },
      ),
    );
  }
}

class _CalendarView extends StatefulWidget {
  final Map<DateTime, List<Workout>> workoutsByDay;

  const _CalendarView({required this.workoutsByDay});

  @override
  State<_CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<_CalendarView> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  String _formatDetailDate(DateTime date) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${days[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  void _showWorkoutDetail(BuildContext context, DateTime day, List<Workout> workouts) {
    // FIX: read weight unit synchronously from registered SharedPreferences singleton
    final weightUnit = sl<SharedPreferences>().getString('weight_unit') ?? 'kg';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFDF8F3),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _WorkoutDetailSheet(
        day: day,
        workouts: workouts,
        formattedDate: _formatDetailDate(day),
        weightUnit: weightUnit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          enabledDayPredicate: (day) {
            final today = DateTime.now();
            final todayNorm = DateTime(today.year, today.month, today.day);
            final dayNorm = DateTime(day.year, day.month, day.day);
            return !dayNorm.isAfter(todayNorm);
          },
          calendarFormat: CalendarFormat.month,
          onPageChanged: (day) => setState(() => _focusedDay = day),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
            final key = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
            final dayWorkouts = widget.workoutsByDay[key] ?? [];
            _showWorkoutDetail(context, selectedDay, dayWorkouts);
          },
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: GoogleFonts.playfairDisplay(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1C0F08),
            ),
            leftChevronIcon: const Icon(Icons.chevron_left, color: Color(0xFF6B4226)),
            rightChevronIcon: const Icon(Icons.chevron_right, color: Color(0xFF6B4226)),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: GoogleFonts.dmSans(
              color: const Color(0xFF4A3728),
              fontSize: 13,
            ),
            weekendStyle: GoogleFonts.dmSans(
              color: const Color(0xFF6B4226),
              fontSize: 13,
            ),
          ),
          calendarStyle: CalendarStyle(
            defaultTextStyle: GoogleFonts.dmSans(
              color: const Color(0xFF1C0F08),
              fontSize: 14,
            ),
            weekendTextStyle: GoogleFonts.dmSans(
              color: const Color(0xFF6B4226),
              fontSize: 14,
            ),
            outsideTextStyle: GoogleFonts.dmSans(
              color: const Color(0xFFCFB99A),
              fontSize: 14,
            ),
            todayDecoration: const BoxDecoration(
              color: Color(0xFF6B4226),
              shape: BoxShape.circle,
            ),
            todayTextStyle: GoogleFonts.dmSans(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            selectedDecoration: const BoxDecoration(
              color: Color(0xFFBF8B5E),
              shape: BoxShape.circle,
            ),
            selectedTextStyle: GoogleFonts.dmSans(
              color: Colors.white,
              fontSize: 14,
            ),
            markerDecoration: const BoxDecoration(
              color: Color(0xFF6B4226),
              shape: BoxShape.circle,
            ),
            tableBorder: const TableBorder(),
          ),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, day, events) {
              final key = DateTime(day.year, day.month, day.day);
              final hasWorkout = widget.workoutsByDay.containsKey(key);
              if (!hasWorkout) return null;
              return Positioned(
                bottom: 2,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6B4226),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(color: cs.primary),
            const SizedBox(width: 6),
            Text(
              'Workout day',
              style: GoogleFonts.dmSans(
                color: const Color(0xFF4A3728),
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 20),
            _LegendDot(color: cs.outline),
            const SizedBox(width: 6),
            Text(
              'Rest day',
              style: GoogleFonts.dmSans(
                color: const Color(0xFF4A3728),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;

  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _WorkoutDetailSheet extends StatelessWidget {
  final DateTime day;
  final List<Workout> workouts;
  final String formattedDate;
  final String weightUnit;

  const _WorkoutDetailSheet({
    required this.day,
    required this.workouts,
    required this.formattedDate,
    this.weightUnit = 'kg',
  });

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCFB99A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              formattedDate,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            if (workouts.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No workouts logged on this day',
                    style: TextStyle(color: Color(0xFF8B7355), fontSize: 15),
                  ),
                ),
              )
            else
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: workouts.length,
                itemBuilder: (context, wi) {
                  final w = workouts[wi];
                  final totalSets = w.exercises.fold(0, (s, e) => s + e.sets.length);
                  final totalVolume = w.exercises.fold(0.0,
                      (s, e) => s + e.sets.fold(0.0, (sv, set) => sv + set.reps * set.weight));

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '⏱ ${_formatDuration(w.durationSeconds)}',
                                style: GoogleFonts.dmSans(
                                  color: cs.primary,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                '${w.exercises.length} exercises · $totalSets sets · ${formatWeight(totalVolume, weightUnit, decimals: 0)} $weightUnit',
                                style: GoogleFonts.dmSans(
                                  color: const Color(0xFF8B7355),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...w.exercises.map((exercise) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      exercise.name,
                                      style: GoogleFonts.dmSans(
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF1C0F08),
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ...exercise.sets.asMap().entries.map((e) => Text(
                                          'Set ${e.key + 1}: ${e.value.reps} reps × ${formatWeight(e.value.weight, weightUnit)} $weightUnit',
                                          style: GoogleFonts.dmSans(
                                            color: const Color(0xFF4A3728),
                                            fontSize: 14,
                                          ),
                                        )),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Close',
                style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
