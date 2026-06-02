import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../injection_container.dart';
import 'blocs/rest_timer/rest_timer_bloc.dart';
import 'blocs/settings/settings_bloc.dart';
import 'blocs/settings/settings_event.dart';
import 'blocs/streak/streak_bloc.dart';
import 'blocs/streak/streak_event.dart';
import 'blocs/workout/workout_bloc.dart';
import 'blocs/workout/workout_event.dart';
import 'blocs/workout_timer/workout_timer_bloc.dart';
import 'blocs/workout_timer/workout_timer_event.dart';
import 'screens/active_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';

GoRouter createRouter(bool onboardingComplete) {
  return GoRouter(
    initialLocation: onboardingComplete ? '/' : '/onboarding',
    redirect: (context, state) {
      final onboardingDone = sl<SharedPreferences>().getBool('onboarding_complete') ?? false;
      if (!onboardingDone && state.matchedLocation != '/onboarding') {
        return '/onboarding';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => sl<StreakBloc>()..add(const StreakLoaded()),
            ),
            // FIX: SettingsBloc on HomeScreen so weight unit loads on app open
            BlocProvider(
              create: (_) => sl<SettingsBloc>()..add(const SettingsLoaded()),
            ),
          ],
          child: const HomeScreen(),
        ),
      ),
      GoRoute(
        path: '/active',
        builder: (context, state) => MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) => sl<WorkoutBloc>()..add(const WorkoutStarted()),
            ),
            BlocProvider(
              create: (_) => sl<WorkoutTimerBloc>()..add(const WorkoutTimerStarted()),
            ),
            BlocProvider(create: (_) => sl<RestTimerBloc>()),
            // FIX: SettingsBloc needed for weight unit toggle on active screen
            BlocProvider(
              create: (_) => sl<SettingsBloc>()..add(const SettingsLoaded()),
            ),
          ],
          child: const ActiveScreen(),
        ),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => HistoryScreen(key: UniqueKey()),
      ),
      GoRoute(
        path: '/calendar',
        builder: (context, state) => const CalendarScreen(),
      ),
    ],
    // FIX: themed error page with home navigation
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(
        title: Text(
          'Page Not Found',
          style: GoogleFonts.playfairDisplay(
            color: const Color(0xFF1C0F08),
          ),
        ),
        backgroundColor: const Color(0xFFFDF8F3),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'No route found for: ${state.uri}',
              style: GoogleFonts.dmSans(
                color: const Color(0xFF4A3728),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: Text(
                'Go Home',
                style: GoogleFonts.dmSans(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
