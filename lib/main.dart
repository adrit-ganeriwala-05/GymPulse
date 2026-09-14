import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import 'injection_container.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'presentation/app_bloc_observer.dart';
import 'presentation/router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Bloc.observer = const AppBlocObserver();
  // Fonts are bundled under assets/fonts; fail loudly if one is missing
  // rather than silently falling back after a network attempt (BUG-21).
  GoogleFonts.config.allowRuntimeFetching = false;
  // Chain, don't replace: the default presents the error; the test binding
  // installs its own handler and asserts it is still in place.
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    developer.log('Flutter error', name: 'gympulse',
        error: details.exception, stackTrace: details.stack);
    previousOnError?.call(details);
  };
  await init();
  final onboardingComplete =
      sl<SharedPreferences>().getBool('onboarding_complete') ?? false;
  runApp(GymPulseApp(router: createRouter(onboardingComplete)));
}

class GymPulseApp extends StatelessWidget {
  final GoRouter router;

  const GymPulseApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'GymPulse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          // ignore: deprecated_member_use
          background: Color(0xFFFDF8F3),
          surface: Color(0xFFF5EDE0),
          // ignore: deprecated_member_use
          surfaceVariant: Color(0xFFEDE0D0),
          primary: Color(0xFF6B4226),
          primaryContainer: Color(0xFF8B5E3C),
          secondary: Color(0xFFA0522D),
          secondaryContainer: Color(0xFFD4956A),
          tertiary: Color(0xFFBF8B5E),
          tertiaryContainer: Color(0xFFE8D5C0),
          // ignore: deprecated_member_use
          onBackground: Color(0xFF1C0F08),
          onSurface: Color(0xFF1C0F08),
          onPrimary: Color(0xFFFDF8F3),
          onSecondary: Color(0xFFFDF8F3),
          outline: Color(0xFFCFB99A),
          outlineVariant: Color(0xFFE8D5C0),
          shadow: Color(0xFF6B4226),
          scrim: Color(0xFF1C0F08),
        ),
        scaffoldBackgroundColor: const Color(0xFFFDF8F3),
        cardTheme: CardThemeData(
          color: const Color(0xFFF5EDE0),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(
              color: Color(0xFFCFB99A),
              width: 1,
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6B4226),
            foregroundColor: const Color(0xFFFDF8F3),
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 2,
            shadowColor: const Color(0x406B4226),
            textStyle: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFFFDF8F3),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          titleTextStyle: GoogleFonts.playfairDisplay(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1C0F08),
          ),
          iconTheme: const IconThemeData(
            color: Color(0xFF6B4226),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5EDE0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFCFB99A)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFCFB99A)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF6B4226), width: 2),
          ),
          labelStyle: GoogleFonts.dmSans(
            color: const Color(0xFF8B7355),
            fontSize: 14,
          ),
          hintStyle: GoogleFonts.dmSans(
            color: const Color(0xFFB09070),
            fontSize: 14,
          ),
        ),
        textTheme: TextTheme(
          displayLarge: GoogleFonts.playfairDisplay(
            fontSize: 56,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF2C1810),
            letterSpacing: -1.5,
          ),
          displayMedium: GoogleFonts.playfairDisplay(
            fontSize: 40,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF2C1810),
            letterSpacing: -1,
          ),
          displaySmall: GoogleFonts.playfairDisplay(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF2C1810),
          ),
          headlineLarge: GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF2C1810),
          ),
          headlineMedium: GoogleFonts.playfairDisplay(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF2C1810),
          ),
          headlineSmall: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF2C1810),
          ),
          titleLarge: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF2C1810),
          ),
          titleMedium: GoogleFonts.playfairDisplay(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF2C1810),
          ),
          titleSmall: GoogleFonts.playfairDisplay(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF2C1810),
          ),
          bodyLarge: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF4A3728),
          ),
          bodyMedium: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF4A3728),
          ),
          bodySmall: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF8B7355),
          ),
          labelLarge: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
          labelMedium: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF4A3728),
          ),
          labelSmall: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF8B7355),
          ),
        ),
      ),
      routerConfig: router,
    );
  }
}
