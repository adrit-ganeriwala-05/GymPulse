import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class StreakCard extends StatelessWidget {
  final int streak;
  final int restDays;

  const StreakCard({super.key, required this.streak, required this.restDays});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text('🔥', style: TextStyle(fontSize: 48)),
                const SizedBox(width: 8),
                Text(
                  '$streak',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
            Text(
              'day streak',
              style: GoogleFonts.dmSans(
                color: cs.onSurface.withValues(alpha: 0.6),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '🗓 $restDays rest days remaining this week',
                  style: GoogleFonts.dmSans(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/calendar'),
                  child: Text(
                    'Calendar',
                    style: GoogleFonts.dmSans(color: cs.primary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
