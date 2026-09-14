import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Rendered when a FutureBuilder's snapshot has an error. Distinct from the
/// empty state on purpose: "couldn't load" must never look like "no data".
class LoadErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const LoadErrorView({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.secondary),
            const SizedBox(height: 12),
            Text(
              "Couldn't load your workouts",
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your data is still on this device. Try again.',
              style: GoogleFonts.dmSans(color: const Color(0xFF8B7355)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
