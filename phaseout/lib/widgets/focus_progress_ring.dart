// ─────────────────────────────────────────────────────────────
//  lib/widgets/focus_progress_ring.dart
//  PhaseOut — Circular focus session progress ring
// ─────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:flutter/material.dart';
import '../app_theme.dart';

class FocusProgressRing extends StatelessWidget {

  final Duration elapsed;
  final bool     active;

  const FocusProgressRing({
    super.key,
    required this.elapsed,
    required this.active,
  });

  String get _label {
    final h = elapsed.inHours;
    final m = elapsed.inMinutes % 60;
    final s = elapsed.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    // Ring fills up every 60 minutes
    final fraction = (elapsed.inSeconds % 3600) / 3600.0;

    return SizedBox(
      width: 160, height: 160,
      child: CustomPaint(
        painter: _RingPainter(
          fraction: fraction,
          active:   active,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                active ? _label : '0s',
                style: const TextStyle(
                  fontSize:   24,
                  fontWeight: FontWeight.w700,
                  color:      AppTheme.textPrimary,
                ),
              ),
              const Text('focused',
                style: TextStyle(
                  fontSize: 11,
                  color:    AppTheme.textSecond,
                )),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {

  final double fraction;
  final bool   active;

  _RingPainter({required this.fraction, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final cx     = size.width / 2;
    final cy     = size.height / 2;
    final radius = (size.width / 2) - 10;
    const stroke = 8.0;

    // Background ring
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..color       = const Color(0xFF1F3A5F)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    if (!active) return;

    // Progress arc
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      -pi / 2,
      2 * pi * fraction,
      false,
      Paint()
        ..color       = AppTheme.warning
        ..style       = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap   = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.active != active;
}