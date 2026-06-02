import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CircularTimer extends StatelessWidget {
  final double progress;
  final String centerText;
  final String labelText;
  final double size;
  final double strokeWidth;
  final Color progressColor;
  final Color trackColor;

  const CircularTimer({
    super.key,
    required this.progress,
    required this.centerText,
    required this.labelText,
    this.size = 200,
    this.strokeWidth = 10,
    this.progressColor = const Color(0xFF6B4226),
    this.trackColor = const Color(0xFFE8D5C0),
  });

  @override
  Widget build(BuildContext context) {
    final centerFontSize = size >= 250 ? 72.0 : 32.0;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CircularTimerPainter(
          progress: progress,
          progressColor: progressColor,
          trackColor: trackColor,
          strokeWidth: strokeWidth,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerText,
                style: GoogleFonts.playfairDisplay(
                  fontSize: centerFontSize,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1C0F08),
                ),
              ),
              Text(
                labelText,
                style: GoogleFonts.dmSans(
                  color: const Color(0xFF8B7355),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircularTimerPainter extends CustomPainter {
  final double progress;
  final Color progressColor;
  final Color trackColor;
  final double strokeWidth;

  _CircularTimerPainter({
    required this.progress,
    required this.progressColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    final sweepAngle = 2 * pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_CircularTimerPainter old) =>
      old.progress != progress ||
      old.progressColor != progressColor ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
