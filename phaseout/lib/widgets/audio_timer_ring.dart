// ─────────────────────────────────────────────────────────────
//  lib/widgets/audio_timer_ring.dart
//  PhaseOut — Countdown ring for audio sleep timer
// ─────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:flutter/material.dart';
import '../app_theme.dart';

class AudioTimerRing extends StatelessWidget {

  final int?   totalMinutes;    // null = no timer active
  final int?   remainingSeconds;

  const AudioTimerRing({
    super.key,
    required this.totalMinutes,
    required this.remainingSeconds,
  });

  double get _fraction {
    if (totalMinutes == null || remainingSeconds == null) return 0;
    final total = totalMinutes! * 60;
    if (total == 0) return 0;
    return (remainingSeconds! / total).clamp(0.0, 1.0);
  }

  String get _label {
    if (remainingSeconds == null || remainingSeconds! <= 0) {
      return 'Off';
    }
    final m = remainingSeconds! ~/ 60;
    final s = remainingSeconds! % 60;
    if (m == 0) return '${s}s';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final active = remainingSeconds != null && remainingSeconds! > 0;

    return SizedBox(
      width: 200, height: 200,
      child: CustomPaint(
        painter: _RingPainter(fraction: _fraction, active: active),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_note_rounded,
                color: active ? AppTheme.tealLight : AppTheme.textHint,
                size:  28,
              ),
              const SizedBox(height: 4),
              Text(
                _label,
                style: TextStyle(
                  fontSize:   32,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? AppTheme.textPrimary
                      : AppTheme.textHint,
                ),
              ),
              Text(
                active ? 'remaining' : 'no timer',
                style: const TextStyle(
                  fontSize: 11,
                  color:    AppTheme.textSecond,
                ),
              ),
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
    final radius = (size.width / 2) - 12;
    const stroke = 10.0;

    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..color       = const Color(0xFF1F3A5F)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    if (!active || fraction <= 0) return;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      -pi / 2,
      2 * pi * fraction,
      false,
      Paint()
        ..color       = AppTheme.teal
        ..style       = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap   = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.active != active;
}