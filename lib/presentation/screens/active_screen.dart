import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../blocs/rest_timer/rest_timer_bloc.dart';
import '../blocs/rest_timer/rest_timer_event.dart';
import '../blocs/rest_timer/rest_timer_state.dart';
import '../blocs/settings/settings_bloc.dart';
import '../blocs/settings/settings_event.dart';
import '../blocs/settings/settings_state.dart';
import '../blocs/workout/workout_bloc.dart';
import '../blocs/workout/workout_event.dart';
import '../blocs/workout/workout_state.dart';
import '../blocs/workout_timer/workout_timer_bloc.dart';
import '../blocs/workout_timer/workout_timer_event.dart';
import '../blocs/workout_timer/workout_timer_state.dart';
import '../format.dart';
import '../widgets/circular_timer.dart';
import '../widgets/exercise_log_card.dart';

class ActiveScreen extends StatelessWidget {
  const ActiveScreen({super.key});

  // canPop:false routes the system back gesture here instead of popping.
  Future<void> _onPopInvoked(BuildContext context, bool didPop) async {
    if (didPop) return;
    final state = context.read<WorkoutBloc>().state;
    // A session is written through as a draft, so leaving is lossless (Home
    // offers Resume/Discard). Only an unsaved *edit* needs confirming.
    final unsavedEdit = state is WorkoutInProgressState && state.isEditing;
    if (!unsavedEdit) {
      if (state is WorkoutInProgressState && state.exercises.isNotEmpty) {
        // The user's model is "leaving loses it"; say the opposite is true.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved as draft — resume from Home',
              style: GoogleFonts.dmSans(color: Colors.white),
            ),
            backgroundColor: const Color(0xFF6B4226),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      context.go('/');
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Edits to this workout will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && context.mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onPopInvoked(context, didPop),
      child: Scaffold(
        appBar: AppBar(
          title: BlocBuilder<WorkoutBloc, WorkoutState>(
          builder: (_, s) => Text(
            s is WorkoutInProgressState && s.isEditing
                ? 'Edit Workout'
                : 'Active Workout',
          ),
        ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: const _ActiveBody(),
        // The full-width FAB floats up with the keyboard and lands exactly over
        // the reps/weight entry row, swallowing the ✓ tap. Hide it while typing.
        floatingActionButton: MediaQuery.viewInsetsOf(context).bottom > 0
            ? null
            : const _FinishButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }
}

class _ActiveBody extends StatelessWidget {
  const _ActiveBody();

  @override
  Widget build(BuildContext context) {
    // Start the stopwatch once, when the session first becomes known, seeded
    // with whatever has already elapsed (0 for new, wall-clock delta for a
    // resumed draft, saved duration for an edit).
    return BlocListener<WorkoutBloc, WorkoutState>(
      listenWhen: (prev, cur) =>
          cur is WorkoutInProgressState &&
          (prev is WorkoutInitialState || prev is WorkoutLoadingState),
      listener: (ctx, state) {
        final s = state as WorkoutInProgressState;
        final from =
            s.isEditing ? s.editing!.durationSeconds : s.elapsedSeconds;
        // Edit mode starts paused: the duration is a saved fact being
        // edited, not a live session — a running clock would inflate it.
        ctx.read<WorkoutTimerBloc>().add(WorkoutTimerStarted(
          from: from,
          paused: s.isEditing || s.timerPaused,
        ));
      },
      child: BlocListener<WorkoutTimerBloc, WorkoutTimerState>(
        // Checkpoint the stopwatch into the draft every 10 s and whenever it
        // pauses/stops, so a kill loses at most 10 s of active time.
        // Also on the pause->running edge so the paused flag clears at once
        // rather than at the next 10 s tick.
        listenWhen: (prev, cur) =>
            cur is WorkoutTimerPausedState ||
            cur is WorkoutTimerStoppedState ||
            (cur is WorkoutTimerRunningState &&
                (cur.seconds % 10 == 0 || prev is! WorkoutTimerRunningState)),
        listener: (ctx, state) {
          final seconds = switch (state) {
            WorkoutTimerRunningState s => s.seconds,
            WorkoutTimerPausedState s => s.seconds,
            WorkoutTimerStoppedState s => s.seconds,
            _ => 0,
          };
          // Stopped is persisted as paused: on resume the user should not
          // find the clock running again.
          final paused = state is! WorkoutTimerRunningState;
          ctx.read<WorkoutBloc>().add(
                WorkoutElapsedUpdated(seconds, paused: paused),
              );
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: const [
            _WorkoutTimerSection(),
            SizedBox(height: 20),
            _ExerciseSection(),
          ],
        ),
      ),
    );
  }
}

class _WorkoutTimerSection extends StatelessWidget {
  const _WorkoutTimerSection();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: BlocBuilder<WorkoutTimerBloc, WorkoutTimerState>(
          builder: (context, state) {
            final seconds = switch (state) {
              WorkoutTimerRunningState s => s.seconds,
              WorkoutTimerStoppedState s => s.seconds,
              WorkoutTimerPausedState s => s.seconds,
              _ => 0,
            };
            final progress = (seconds / 3600).clamp(0.0, 1.0);

            return Column(
              children: [
                CircularTimer(
                  progress: progress,
                  centerText: formatDuration(seconds),
                  labelText: 'workout duration',
                  size: 200,
                  strokeWidth: 10,
                  progressColor: cs.primary,
                  trackColor: cs.outlineVariant,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (state is WorkoutTimerInitialState)
                      _timerBtn(
                        context,
                        Icons.play_arrow,
                        'Start',
                        cs.primary,
                        () => context.read<WorkoutTimerBloc>().add(const WorkoutTimerStarted()),
                      ),
                    if (state is WorkoutTimerRunningState) ...[
                      _timerBtn(
                        context,
                        Icons.pause,
                        'Pause',
                        cs.primary,
                        () => context.read<WorkoutTimerBloc>().add(const WorkoutTimerPaused()),
                      ),
                      const SizedBox(width: 12),
                      _timerBtn(
                        context,
                        Icons.stop,
                        'Stop',
                        Colors.red.shade300,
                        () => context.read<WorkoutTimerBloc>().add(const WorkoutTimerStopped()),
                      ),
                    ],
                    if (state is WorkoutTimerPausedState) ...[
                      _timerBtn(
                        context,
                        Icons.play_arrow,
                        'Resume',
                        cs.primary,
                        () => context.read<WorkoutTimerBloc>().add(const WorkoutTimerResumed()),
                      ),
                      const SizedBox(width: 12),
                      _timerBtn(
                        context,
                        Icons.stop,
                        'Stop',
                        Colors.red.shade300,
                        () => context.read<WorkoutTimerBloc>().add(const WorkoutTimerStopped()),
                      ),
                    ],
                    if (state is WorkoutTimerStoppedState)
                      _timerBtn(
                        context,
                        Icons.refresh,
                        'Reset',
                        cs.outline,
                        () => context.read<WorkoutTimerBloc>().add(const WorkoutTimerReset()),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _timerBtn(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        elevation: 0,
      ),
    );
  }
}

class _ExerciseSection extends StatefulWidget {
  const _ExerciseSection();

  @override
  State<_ExerciseSection> createState() => _ExerciseSectionState();
}

class _ExerciseSectionState extends State<_ExerciseSection> {
  bool _showAddForm = false;
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _openForm() {
    setState(() => _showAddForm = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  void _closeForm() {
    setState(() => _showAddForm = false);
    _ctrl.clear();
    FocusScope.of(context).unfocus();
  }

  void _submit(BuildContext context) {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    final state = context.read<WorkoutBloc>().state;
    if (state is WorkoutInProgressState) {
      final exists = state.exercises.any(
        (e) => e.name.toLowerCase() == name.toLowerCase(),
      );
      if (exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$name" is already added'),
            backgroundColor: const Color(0xFF6B4226),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        return;
      }
    }
    context.read<WorkoutBloc>().add(ExerciseAdded(name));
    _closeForm();
  }

  void _showRestTimerSheet(BuildContext context) {
    // Sets are logged with the reps/weight keyboard open. Opening the sheet
    // in that same frame, while the keyboard is still animating, made the
    // (non-scrollable, ~480px tall) sheet relayout on every viewport-metrics
    // tick and throw '!_debugDoingThisLayout', so only the dark scrim painted.
    // Drop the keyboard first, then open on the next frame once layout settled.
    FocusManager.instance.primaryFocus?.unfocus();
    final bloc = context.read<RestTimerBloc>();
    bloc.add(const RestTimerReset());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: true,
        backgroundColor: const Color(0xFFFDF8F3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => BlocProvider.value(
          value: bloc,
          child: _RestTimerSheetWithListener(parentContext: context),
        ),
      ).whenComplete(() {
        // Whatever closed the sheet (finish, drag, X, back), tear the timer
        // down so its periodic subscription can't keep ticking and emit a
        // stray finished-state with no sheet attached.
        if (!bloc.isClosed) bloc.add(const RestTimerReset());
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, state) {
            final unit = state is SettingsLoadedState ? state.weightUnit : 'kg';
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Weight unit:',
                  style: GoogleFonts.dmSans(
                    color: const Color(0xFF8B7355),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => context.read<SettingsBloc>().add(
                        WeightUnitChanged(unit == 'kg' ? 'lbs' : 'kg'),
                      ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      unit.toUpperCase(),
                      style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        if (!_showAddForm)
          OutlinedButton.icon(
            onPressed: _openForm,
            icon: Icon(Icons.add, color: cs.primary),
            label: Text(
              'Add Exercise',
              style: GoogleFonts.dmSans(
                color: cs.primary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: cs.primary),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        if (_showAddForm)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _ctrl,
                    focusNode: _focusNode,
                    decoration: const InputDecoration(labelText: 'Exercise name'),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(context),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _closeForm,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            side: BorderSide(color: cs.outline),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.dmSans(
                              color: const Color(0xFF8B7355),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _submit(context),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            backgroundColor: cs.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Add',
                            style: GoogleFonts.dmSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        BlocBuilder<WorkoutBloc, WorkoutState>(
          builder: (context, workoutState) {
            return BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, settingsState) {
                final unit = settingsState is SettingsLoadedState
                    ? settingsState.weightUnit
                    : 'kg';

                if (workoutState is WorkoutLoadingState) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (workoutState is! WorkoutInProgressState ||
                    workoutState.exercises.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'Tap "Add Exercise" to start logging',
                        style: GoogleFonts.dmSans(
                          color: const Color(0xFF8B7355),
                          fontSize: 15,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return Column(
                  children: workoutState.exercises.map((exercise) {
                    return ExerciseLogCard(
                      exercise: exercise,
                      weightUnit: unit,
                      onAddSet: (reps, weight) {
                        context.read<WorkoutBloc>().add(
                              SetLogged(
                                exerciseName: exercise.name,
                                reps: reps,
                                weight: weight,
                              ),
                            );
                        _showRestTimerSheet(context);
                      },
                      onRemoveSet: (i) => context.read<WorkoutBloc>().add(
                            SetRemoved(exerciseName: exercise.name, setIndex: i),
                          ),
                      onRemoveExercise: () => context
                          .read<WorkoutBloc>()
                          .add(ExerciseRemoved(exercise.name)),
                    );
                  }).toList(),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _RestTimerSheet extends StatefulWidget {
  const _RestTimerSheet();

  @override
  State<_RestTimerSheet> createState() => _RestTimerSheetState();
}

class _RestTimerSheetState extends State<_RestTimerSheet> {
  int _selectedDuration = 60;
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCFB99A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Rest Timer',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [30, 60, 90, 120].map((d) {
              final selected = _selectedDuration == d;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedDuration = d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? cs.primary : cs.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? cs.primary : cs.outline,
                      ),
                    ),
                    child: Text(
                      '${d}s',
                      style: GoogleFonts.dmSans(
                        color: selected ? Colors.white : cs.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _customCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Custom seconds',
              helperText: 'Press done to apply (5–3600)',
              isDense: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            // Commit on submit, not per keystroke: typing "120" must not
            // select 1, then 12, then 120.
            onSubmitted: (v) {
              final n = int.tryParse(v);
              if (n != null) setState(() => _selectedDuration = n.clamp(5, 3600));
            },
          ),
          const SizedBox(height: 24),
          BlocBuilder<RestTimerBloc, RestTimerState>(
            builder: (context, state) {
              final seconds = switch (state) {
                RestTimerRunningState s => s.seconds,
                RestTimerPausedState s => s.seconds,
                RestTimerInitialState s => s.seconds,
                _ => 0,
              };
              final total = switch (state) {
                RestTimerRunningState s => s.totalDuration,
                RestTimerPausedState s => s.totalDuration,
                _ => _selectedDuration,
              };
              final progress = total > 0 ? seconds / total : 0.0;
              final isRunning = state is RestTimerRunningState;
              final isPaused = state is RestTimerPausedState;
              final isInitial = state is RestTimerInitialState;

              return Column(
                children: [
                  CircularTimer(
                    progress: progress,
                    centerText: '$seconds',
                    labelText: 'seconds remaining',
                    size: 280,
                    strokeWidth: 10,
                    progressColor: const Color(0xFF6B4226),
                    trackColor: const Color(0xFFE8D5C0),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isInitial)
                        ElevatedButton(
                          onPressed: () => context
                              .read<RestTimerBloc>()
                              .add(RestTimerStarted(_selectedDuration)),
                          // Theme default is minimumSize(double.infinity, 56);
                          // inside this centered Row that is an infinite width
                          // constraint and the sheet body fails to lay out.
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(140, 48),
                          ),
                          child: Text(
                            'Start',
                            style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      if (isRunning)
                        IconButton(
                          iconSize: 36,
                          icon: const Icon(Icons.pause_circle, color: Color(0xFF6B4226)),
                          onPressed: () =>
                              context.read<RestTimerBloc>().add(const RestTimerPaused()),
                        ),
                      if (isPaused)
                        IconButton(
                          iconSize: 36,
                          icon: const Icon(Icons.play_circle, color: Color(0xFF6B4226)),
                          onPressed: () =>
                              context.read<RestTimerBloc>().add(const RestTimerResumed()),
                        ),
                      if (!isInitial) ...[
                        IconButton(
                          iconSize: 36,
                          icon: Icon(Icons.refresh, color: cs.outline),
                          onPressed: () =>
                              context.read<RestTimerBloc>().add(const RestTimerReset()),
                        ),
                        IconButton(
                          iconSize: 36,
                          icon: Icon(Icons.close, color: cs.outline),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                      if (isInitial)
                        IconButton(
                          iconSize: 36,
                          icon: Icon(Icons.close, color: cs.outline),
                          onPressed: () => Navigator.pop(context),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
        ),
      ),
    );
  }
}

class _RestTimerSheetWithListener extends StatefulWidget {
  final BuildContext parentContext;
  const _RestTimerSheetWithListener({required this.parentContext});

  @override
  State<_RestTimerSheetWithListener> createState() =>
      _RestTimerSheetWithListenerState();
}

class _RestTimerSheetWithListenerState
    extends State<_RestTimerSheetWithListener> {
  @override
  Widget build(BuildContext context) {
    return BlocListener<RestTimerBloc, RestTimerState>(
      listener: (ctx, state) {
        if (state is RestTimerFinishedState && mounted) {
          // Defer the pop a frame: firing Navigator.pop() straight out of a
          // bloc state change can land mid-layout and trip
          // '!_debugDoingThisLayout'.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pop();
            Future.delayed(const Duration(milliseconds: 300), () {
              if (widget.parentContext.mounted) {
                ScaffoldMessenger.of(widget.parentContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Rest complete! Time to work 💪',
                      style: GoogleFonts.dmSans(color: Colors.white),
                    ),
                    backgroundColor: const Color(0xFF6B4226),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }
            });
          });
        }
      },
      child: const _RestTimerSheet(),
    );
  }
}

class _FinishButton extends StatefulWidget {
  const _FinishButton();

  @override
  State<_FinishButton> createState() => _FinishButtonState();
}

class _FinishButtonState extends State<_FinishButton> {
  bool _confirming = false;

  void _onFinishTapped() {
    final workoutState = context.read<WorkoutBloc>().state;
    if (workoutState is WorkoutInProgressState &&
        workoutState.exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Add at least one exercise first',
            style: GoogleFonts.dmSans(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF6B4226),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }
    final timerState = context.read<WorkoutTimerBloc>().state;
    if (timerState is WorkoutTimerInitialState) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Timer was never started — duration will be recorded as 0:00',
            style: GoogleFonts.dmSans(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF6B4226),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
    setState(() => _confirming = true);
  }

  void _saveAndFinish() {
    final timerState = context.read<WorkoutTimerBloc>().state;
    final duration = switch (timerState) {
      WorkoutTimerRunningState s => s.seconds,
      WorkoutTimerPausedState s => s.seconds,
      WorkoutTimerStoppedState s => s.seconds,
      _ => 0,
    };
    context.read<WorkoutTimerBloc>().add(const WorkoutTimerStopped());
    context.read<WorkoutBloc>().add(WorkoutFinished(durationSeconds: duration));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Widget content;
    if (_confirming) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: () => setState(() => _confirming = false),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: cs.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Keep Going',
                    style: GoogleFonts.dmSans(
                      color: const Color(0xFF8B7355),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _saveAndFinish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Save & Finish',
                    style: GoogleFonts.dmSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          width: double.infinity,
          child: FloatingActionButton.extended(
            onPressed: _onFinishTapped,
            backgroundColor: cs.secondary,
            foregroundColor: Colors.white,
            label: Text(
              'Finish Workout ✓',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return BlocListener<WorkoutBloc, WorkoutState>(
      listener: (ctx, state) {
        if (state is WorkoutCompleteState) {
          ctx.go('/');
        } else if (state is WorkoutErrorState) {
          setState(() => _confirming = false);
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(
                state.message,
                style: GoogleFonts.dmSans(color: Colors.white),
              ),
              backgroundColor: const Color(0xFF6B4226),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      },
      child: content,
    );
  }
}
