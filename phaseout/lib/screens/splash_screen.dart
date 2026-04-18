// ─────────────────────────────────────────────────────────────
//  lib/screens/splash_screen.dart  — PhaseOut v1.0 final
//  Splash animation → Onboarding (first time) or Dashboard.
//  Animation is untouched and perfect.
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../utils/constants.dart';
import 'dashboard_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  late final AnimationController _moonCtrl;
  late final AnimationController _wordCtrl;
  late final AnimationController _tagCtrl;
  late final AnimationController _glowCtrl;

  late final Animation<double> _moonScale;
  late final Animation<double> _moonOpacity;
  late final Animation<double> _wordOpacity;
  late final Animation<Offset>  _wordSlide;
  late final Animation<double> _tagOpacity;
  late final Animation<double> _glowPulse;

  @override
  void initState() {
    super.initState();

    _moonCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _moonScale   = CurvedAnimation(parent: _moonCtrl, curve: Curves.easeOutBack)
        .drive(Tween(begin: 0.5, end: 1.0));
    _moonOpacity = CurvedAnimation(parent: _moonCtrl, curve: const Interval(0, 0.5))
        .drive(Tween(begin: 0.0, end: 1.0));

    _wordCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _wordOpacity = CurvedAnimation(parent: _wordCtrl, curve: Curves.easeOut)
        .drive(Tween(begin: 0.0, end: 1.0));
    _wordSlide   = CurvedAnimation(parent: _wordCtrl, curve: Curves.easeOut)
        .drive(Tween(begin: const Offset(0, 0.3), end: Offset.zero));

    _tagCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _tagOpacity = CurvedAnimation(parent: _tagCtrl, curve: Curves.easeIn)
        .drive(Tween(begin: 0.0, end: 1.0));

    _glowCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _glowPulse = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut)
        .drive(Tween(begin: 0.6, end: 1.0));

    _runSequence();
  }

  Future<void> _runSequence() async {
    _moonCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    _wordCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _tagCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _navigate();
  }

  Future<void> _navigate() async {
    final prefs     = await SharedPreferences.getInstance();
    final onboarded = prefs.getBool(AppConstants.prefOnboardingDone) ?? false;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder:        (_, __, ___) =>
          onboarded ? const DashboardScreen() : const OnboardingScreen(),
      transitionDuration: const Duration(milliseconds: 500),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  void dispose() {
    _moonCtrl.dispose();
    _wordCtrl.dispose();
    _tagCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: Stack(children: [
        const Positioned.fill(child: _StarField()),

        AnimatedBuilder(
          animation: _glowPulse,
          builder: (_, __) => Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 0.7,
                  colors: [
                    AppTheme.blue.withValues(alpha: 0.08 * _glowPulse.value),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedBuilder(
              animation: _moonCtrl,
              builder: (_, __) => Opacity(
                opacity: _moonOpacity.value,
                child: Transform.scale(
                  scale: _moonScale.value,
                  child: const _MoonIcon(size: 110),
                ),
              ),
            ),
            const SizedBox(height: 36),

            AnimatedBuilder(
              animation: _wordCtrl,
              builder: (_, __) => FadeTransition(
                opacity: _wordOpacity,
                child: SlideTransition(
                  position: _wordSlide,
                  child: const Text('PhaseOut',
                    style: TextStyle(
                      fontFamily:    'DMSerifDisplay',
                      fontSize:      38,
                      color:         AppTheme.textPrimary,
                      letterSpacing: 0.5,
                    )),
                ),
              ),
            ),
            const SizedBox(height: 10),

            AnimatedBuilder(
              animation: _tagCtrl,
              builder: (_, __) => FadeTransition(
                opacity: _tagOpacity,
                child: const Text('Wind down. Sleep better.',
                  style: TextStyle(
                    fontSize:   14,
                    color:      AppTheme.textSecond,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w300,
                  )),
              ),
            ),

            const SizedBox(height: 56),

            AnimatedBuilder(
              animation: _tagCtrl,
              builder: (_, __) => Opacity(
                opacity: _tagOpacity.value,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _dot(18, 5),
                  const SizedBox(width: 8),
                  _dot(5, 5),
                  const SizedBox(width: 8),
                  _dot(4, 4),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _dot(double w, double h) => Container(
    width: w, height: h,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(h / 2),
      color: AppTheme.blueLight.withValues(alpha: 0.5),
    ),
  );
}

class _MoonIcon extends StatelessWidget {
  final double size;
  const _MoonIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
          colors: [Color(0xFF1E3560), Color(0xFF0A1830)],
        ),
        boxShadow: [
          BoxShadow(color: AppTheme.blue.withValues(alpha: 0.3),
              blurRadius: size * 0.5),
          BoxShadow(color: AppTheme.blueLight.withValues(alpha: 0.1),
              blurRadius: size * 0.2, spreadRadius: size * 0.05),
        ],
        border: Border.all(color: AppTheme.border2, width: 1),
      ),
      child: CustomPaint(painter: _MoonPainter()),
    );
  }
}

class _MoonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    canvas.drawCircle(Offset(w*0.46, h*0.50), w*0.26,
        Paint()..color = const Color(0xFFE8F0FF).withValues(alpha: 0.95));
    canvas.drawCircle(Offset(w*0.56, h*0.42), w*0.21,
        Paint()..color = const Color(0xFF0D1628));
    final s = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(Offset(w*0.76, h*0.28), w*0.04, s);
    canvas.drawCircle(Offset(w*0.76, h*0.28), w*0.018,
        Paint()..color = const Color(0xFF60A5FA));
    canvas.drawCircle(Offset(w*0.68, h*0.70), w*0.025, s);
    canvas.drawCircle(Offset(w*0.20, h*0.24), w*0.018,
        Paint()..color = Colors.white.withValues(alpha: 0.6));
  }
  @override bool shouldRepaint(_) => false;
}

class _StarField extends StatelessWidget {
  const _StarField();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _StarPainter());
}

class _StarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);
    final p   = Paint();
    for (var i = 0; i < 80; i++) {
      p.color = Colors.white.withValues(alpha: rng.nextDouble() * 0.5 + 0.15);
      canvas.drawCircle(
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height * 0.85),
        rng.nextDouble() * 1.2 + 0.3, p,
      );
    }
  }
  @override bool shouldRepaint(_) => false;
}