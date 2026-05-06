// ─────────────────────────────────────────────────────────────
//  lib/screens/audio_timer_screen.dart
//
//  FIXES:
//  - remainingDuration() → remainingSeconds() returns int?
//  - AudioTimerService.start() takes int (minutes) not Duration
//  - Navigates to home screen after timer expires (#4)
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../services/audio_timer_service.dart';

class AudioTimerScreen extends StatefulWidget {
  const AudioTimerScreen({super.key});
  @override
  State<AudioTimerScreen> createState() => _AudioTimerScreenState();
}

class _AudioTimerScreenState extends State<AudioTimerScreen>
    with SingleTickerProviderStateMixin {

  static const _channel = MethodChannel('com.brightdev.phaseout/media');

  bool  _active          = false;
  int?  _remainingSeconds;
  int   _selectedMinutes = 30;
  int?  _totalMinutes;
  Timer? _ticker;
  late AnimationController _ringCtrl;

  static const _presets = [15, 30, 45, 60, 90, 120];

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
    _load();
  }

  Future<void> _load() async {
    final active    = await AudioTimerService.isActive();
    // FIX: remainingSeconds() returns int? not Duration?
    final remaining = await AudioTimerService.remainingSeconds();
    if (mounted) {
      setState(() {
        _active           = active;
        _remainingSeconds = remaining;
        _totalMinutes     = active ? _selectedMinutes : null;
      });
      if (active) _startTicker();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      final rem = await AudioTimerService.remainingSeconds();
      if (rem == null || rem <= 0) {
        _ticker?.cancel();
        setState(() {
          _active           = false;
          _remainingSeconds = null;
          _totalMinutes     = null;
        });
        await _goHome();
        return;
      }
      setState(() => _remainingSeconds = rem);
    });
  }

  // #4 — Navigate to home screen after timer stops audio
  Future<void> _goHome() async {
    try { await _channel.invokeMethod('goHome'); } catch (_) {}
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _start() async {
    // FIX: start() takes int minutes, not Duration
    await AudioTimerService.start(_selectedMinutes);
    setState(() {
      _active           = true;
      _remainingSeconds = _selectedMinutes * 60;
      _totalMinutes     = _selectedMinutes;
    });
    _startTicker();
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    await AudioTimerService.cancel();
    if (mounted) {
      setState(() {
        _active           = false;
        _remainingSeconds = null;
        _totalMinutes     = null;
      });
    }
  }

  String _fmt(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
    }
    return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  }

  double get _progress {
    final rem   = _remainingSeconds;
    final total = (_totalMinutes ?? _selectedMinutes) * 60;
    if (!_active || rem == null || total == 0) return 1.0;
    return (rem / total).clamp(0.0, 1.0);
  }

  @override
  void dispose() { _ticker?.cancel(); _ringCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final displaySeconds = _remainingSeconds ?? _selectedMinutes * 60;

    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        title: const Text('Sleep timer'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [

          // Ring
          Center(child: SizedBox(width: 220, height: 220,
            child: Stack(alignment: Alignment.center, children: [
              AnimatedBuilder(animation: _ringCtrl,
                builder: (_, __) => CustomPaint(
                  size: const Size(220, 220),
                  painter: _TimerRing(
                    progress: _progress,
                    active:   _active,
                    t:        _ringCtrl.value))),
              Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bedtime_rounded,
                    color: Color(0xFF60A5FA), size: 28),
                const SizedBox(height: 8),
                Text(_fmt(displaySeconds),
                  style: const TextStyle(fontFamily: 'DMSerifDisplay',
                      fontSize: 38, color: Colors.white, height: 1)),
                const SizedBox(height: 4),
                Text(_active ? 'until audio stops' : 'will stop audio',
                  style: TextStyle(fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5))),
              ]),
            ]),
          )),

          const SizedBox(height: 32),

          // Presets — only when not active
          if (!_active) ...[
            const Text('DURATION', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600,
                color: AppTheme.textHint, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8,
              children: _presets.map((min) {
                final sel = _selectedMinutes == min;
                return GestureDetector(
                  onTap: () => setState(() => _selectedMinutes = min),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: sel
                          ? const Color(0xFF60A5FA).withValues(alpha: 0.15)
                          : AppTheme.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sel
                          ? const Color(0xFF60A5FA).withValues(alpha: 0.5)
                          : AppTheme.border),
                    ),
                    child: Text(
                      min < 60 ? '${min}m' : '${min ~/ 60}h',
                      style: TextStyle(fontSize: 13,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                          color: sel
                              ? const Color(0xFF60A5FA)
                              : AppTheme.textSecond)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // Start / cancel
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: _active ? _cancel : _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: _active
                    ? AppTheme.rose : const Color(0xFF60A5FA),
                padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(
                _active
                    ? 'Cancel timer'
                    : 'Start ${_selectedMinutes}min timer',
                style: const TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w600, color: Colors.white)),
            )),

          if (_active) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF60A5FA).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF60A5FA).withValues(alpha: 0.15)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: Color(0xFF60A5FA)),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'Audio will stop and the app will return to home when the timer ends.',
                  style: TextStyle(fontSize: 11,
                      color: AppTheme.textSecond, height: 1.5))),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimerRing extends CustomPainter {
  final double progress, t;
  final bool   active;
  const _TimerRing({required this.progress,
      required this.active, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2; final cy = size.height / 2;
    final r  = size.width / 2 - 10;
    canvas.drawCircle(Offset(cx, cy), r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = Colors.white.withValues(alpha: 0.07));
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -math.pi / 2,
      2 * math.pi * progress, false,
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap   = StrokeCap.round
        ..color       = active
            ? const Color(0xFF60A5FA)
            : const Color(0xFF60A5FA).withValues(alpha: 0.25),
    );
    if (active && progress > 0.01) {
      final angle = -math.pi / 2 + 2 * math.pi * progress;
      canvas.drawCircle(
        Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)),
        6, Paint()..color = const Color(0xFF60A5FA));
    }
  }

  @override
  bool shouldRepaint(_TimerRing old) =>
      old.progress != progress || old.t != t;
}