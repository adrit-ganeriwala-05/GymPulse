import 'package:flutter/material.dart';

class TimerDisplay extends StatelessWidget {
  final int seconds;
  final TextStyle? style;

  const TimerDisplay({super.key, required this.seconds, this.style});

  String _format(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _format(seconds),
      style: style ??
          const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
    );
  }
}
