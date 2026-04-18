// ─────────────────────────────────────────────────────────────
//  lib/screens/focus_lock_overlay.dart
//  PhaseOut — Focus mode lock overlay
//
//  Shown as a system overlay when a blocked app is detected.
//  Simple, non-distracting design — moon character, message,
//  and a single button to return to allowed apps.
//
//  NOTE: Requires SYSTEM_ALERT_WINDOW permission.
//  For MVP this is shown as a full-screen route pushed over
//  the blocked app. True system overlay is v1.1 (Kotlin).
// ─────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../services/focus_service.dart';

class FocusLockOverlay extends StatefulWidget {
  final String blockedPackage;
  final List<String> allowlist;

  const FocusLockOverlay({
    super.key,
    required this.blockedPackage,
    required this.allowlist,
  });

  @override
  State<FocusLockOverlay> createState() => _FocusLockOverlayState();
}

class _FocusLockOverlayState extends State<FocusLockOverlay>
    with TickerProviderStateMixin {

  late final AnimationController _pulseCtrl;
  late final AnimationController _entryCtrl;
  late final Animation<double>   _pulse;
  late final Animation<double>   _entryOpacity;
  late final Animation<Offset>   _entrySlide;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    _entryOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut),
    );
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  String get _appName {
    final parts = widget.blockedPackage.split('.');
    final raw   = parts.last;
    return raw.isEmpty ? widget.blockedPackage
        : raw[0].toUpperCase() + raw.substring(1);
  }

  Future<void> _endSession() async {
    await FocusService.stopSession();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [

        // ── Blurred dark background ──────────────────────
        Positioned.fill(
          child: CustomPaint(painter: _OverlayBgPainter()),
        ),

        // ── Content ─────────────────────────────────────
        FadeTransition(
          opacity: _entryOpacity,
          child: SlideTransition(
            position: _entrySlide,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [

                      // Moon character — animated pulse
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, __) => Transform.scale(
                          scale: _pulse.value,
                          child: const _MoonCharacter(size: 120),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Blocked message
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                              color: AppTheme.danger.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '$_appName is blocked',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.danger,
                            fontWeight: FontWeight.w600,
                          )),
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'Stay focused.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily:  'DMSerifDisplay',
                          fontSize:    32,
                          color:       Colors.white,
                          letterSpacing: 0.5,
                          height: 1.1,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'You\'re in a focus session.\nThis app is not in your allowed list.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.55),
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Go back button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                AppTheme.accentLight.withValues(alpha: 0.15),
                            foregroundColor: AppTheme.accentLight,
                            side: BorderSide(
                                color: AppTheme.accentLight
                                    .withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 15),
                          ),
                          child: const Text('Go back',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            )),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // End session link
                      TextButton(
                        onPressed: _endSession,
                        child: Text(
                          'End focus session',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Moon character painter ────────────────────────────────────
class _MoonCharacter extends StatelessWidget {
  final double size;
  const _MoonCharacter({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MoonCharacterPainter()),
    );
  }
}

class _MoonCharacterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w  = size.width;
    final h  = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // Outer glow
    canvas.drawCircle(
      Offset(cx, cy), w * 0.48,
      Paint()
        ..color = const Color(0xFF60A5FA).withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    // Moon body
    canvas.drawCircle(
      Offset(cx, cy), w * 0.38,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );

    // Crescent cutout
    canvas.drawCircle(
      Offset(cx + w * 0.14, cy - h * 0.1), w * 0.30,
      Paint()..color = const Color(0xFF060F1E),
    );

    // Eyes — simple dots
    final eyePaint = Paint()..color = const Color(0xFF0A1628);

    // Left eye
    canvas.drawCircle(Offset(cx - w * 0.08, cy - h * 0.04), w * 0.03, eyePaint);
    // Right eye — barely visible on crescent edge
    canvas.drawCircle(Offset(cx + w * 0.01, cy - h * 0.06), w * 0.025, eyePaint);

    // Smile — small arc
    final smileyRect = Rect.fromCenter(
      center: Offset(cx - w * 0.04, cy + h * 0.06),
      width:  w * 0.15,
      height: h * 0.08,
    );
    canvas.drawArc(
      smileyRect,
      0,
      math.pi,
      false,
      Paint()
        ..color = const Color(0xFF0A1628)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.025
        ..strokeCap = StrokeCap.round,
    );

    // Three phase stars/dots around the moon
    final starPaint = Paint()
      ..color = const Color(0xFF60A5FA).withValues(alpha: 0.7);

    canvas.drawCircle(Offset(cx + w * 0.42, cy - h * 0.30), w * 0.025, starPaint);
    canvas.drawCircle(Offset(cx - w * 0.38, cy - h * 0.20), w * 0.018, starPaint);
    canvas.drawCircle(Offset(cx + w * 0.38, cy + h * 0.25), w * 0.015, starPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Background painter ────────────────────────────────────────
class _OverlayBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Deep translucent navy — semi-transparent so user sees they
    // are blocked but can't interact with the app behind
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xF0040D1A),
    );

    // Subtle radial vignette to focus the eye on center
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.8,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.4),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(_) => false;
}