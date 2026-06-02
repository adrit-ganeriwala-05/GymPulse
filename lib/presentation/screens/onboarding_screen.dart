import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../injection_container.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _nameController = TextEditingController();
  int _page = 0;
  String? _nameError;

  static const _pages = [
    _OnboardingPageData(
      emoji: '🏋️',
      title: 'Welcome to GymPulse',
      subtitle: 'Your personal fitness companion.\nBuilt for athletes who mean business.',
    ),
    _OnboardingPageData(
      emoji: '🔥',
      title: 'Build Your Streak',
      subtitle: 'Track every workout.\nProtect your streak.\nTwo rest days per week — use them wisely.',
    ),
    _OnboardingPageData(
      emoji: '⏱',
      title: 'Time Every Rep',
      subtitle: 'Workout timer. Rest timer.\nEverything you need to train smarter.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleNext() async {
    if (_page == 0) {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        setState(() => _nameError = 'Please enter your name');
        return;
      }
      await sl<SharedPreferences>().setString('user_name', name);
      setState(() => _nameError = null);
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
  }

  Future<void> _complete() async {
    final prefs = sl<SharedPreferences>();
    await prefs.setBool('onboarding_complete', true);
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      await prefs.setString('user_name', name);
    }
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return _NameInputPage(
                      data: _pages[i],
                      nameController: _nameController,
                      nameError: _nameError,
                    );
                  }
                  return _OnboardingPage(data: _pages[i]);
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  width: _page == i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _page == i ? cs.primary : cs.outline,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: _page == _pages.length - 1
                  ? ElevatedButton(
                      onPressed: _complete,
                      child: Text(
                        'Get Started',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _handleNext,
                      child: Text(
                        'Next',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  final String emoji;
  final String title;
  final String subtitle;

  const _OnboardingPageData({
    required this.emoji,
    required this.title,
    required this.subtitle,
  });
}

class _NameInputPage extends StatelessWidget {
  final _OnboardingPageData data;
  final TextEditingController nameController;
  final String? nameError;

  const _NameInputPage({
    required this.data,
    required this.nameController,
    required this.nameError,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          Text(data.emoji, style: const TextStyle(fontSize: 100)),
          const SizedBox(height: 32),
          Text(
            data.title,
            style: GoogleFonts.playfairDisplay(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            data.subtitle,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              color: const Color(0xFF4A3728),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 36),
          TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: 'What should we call you?',
              hintText: 'Enter your name',
              errorText: nameError,
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;

  const _OnboardingPage({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(data.emoji, style: const TextStyle(fontSize: 120)),
          const SizedBox(height: 40),
          Text(
            data.title,
            style: GoogleFonts.playfairDisplay(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            data.subtitle,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              color: const Color(0xFF4A3728),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
