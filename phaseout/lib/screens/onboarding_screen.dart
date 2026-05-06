// ─────────────────────────────────────────────────────────────
//  lib/screens/onboarding_screen.dart
//
//  FIX: Removed unused import 'dashboard_screen.dart'
// ─────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../utils/constants.dart';
import 'schedule_builder_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {

  final _ctrl = PageController();
  int   _page = 0;
  bool  _asking = false;

  late final AnimationController _skyCtrl;

  @override
  void initState() {
    super.initState();
    _skyCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 80))
      ..repeat();
  }

  @override
  void dispose() { _skyCtrl.dispose(); _ctrl.dispose(); super.dispose(); }

  Future<void> _next() async {
    if (_page == 1) {
      setState(() => _asking = true);
      await Permission.notification.request();
      setState(() => _asking = false);
    } else if (_page == 2) {
      setState(() => _asking = true);
      await Permission.ignoreBatteryOptimizations.request();
      setState(() => _asking = false);
    }

    if (_page < 3) {
      _ctrl.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut);
      setState(() => _page++);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefOnboardingDone, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
          builder: (_) => const ScheduleBuilderScreen(isFirstTime: true)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: Stack(children: [

        Positioned.fill(child: AnimatedBuilder(
          animation: _skyCtrl,
          builder: (_, __) => CustomPaint(
            painter: _OnboardingSkyPainter(t: _skyCtrl.value)),
        )),

        SafeArea(child: Column(children: [

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(children: [
              const Text('PhaseOut', style: TextStyle(
                  fontFamily: 'DMSerifDisplay',
                  fontSize: 18, color: Colors.white)),
              const Spacer(),
              Row(children: List.generate(4, (i) => Container(
                margin: const EdgeInsets.only(left: 5),
                width: i == _page ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page
                      ? AppTheme.accentLight
                      : Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3))))),
            ]),
          ),

          Expanded(child: PageView(
            controller: _ctrl,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              _Page(
                emoji: '🌙',
                title: 'Your phone.\nYour rules.',
                body:  'PhaseOut automates your bedtime routine so you don\'t '
                       'have to think about it. Set a schedule once — it runs every night.',
                note:  null),
              _Page(
                emoji: '🔔',
                title: 'Stay in the\nloop.',
                body:  'PhaseOut needs to send notifications for bedtime reminders '
                       'and schedule alerts. We\'ll ask for permission now.',
                note:  'You\'ll see an Android permission dialog.'),
              _Page(
                emoji: '🔋',
                title: 'Runs all\nnight.',
                body:  'Android sometimes stops background apps to save battery. '
                       'Disabling battery optimisation for PhaseOut ensures your '
                       'schedule fires reliably at 2 AM.',
                note:  'You\'ll be taken to Android settings to allow this.'),
              _Page(
                emoji: '✅',
                title: 'You\'re all\nset.',
                body:  'Other permissions (screen time, focus mode, Do Not Disturb) '
                       'will be requested when you use those features — only when '
                       'you need them.',
                note:  'Let\'s build your first schedule.'),
            ],
          )),

          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20,
                MediaQuery.of(context).padding.bottom + 32),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _asking ? null : _next,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppTheme.accent),
                child: _asking
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        _page < 3 ? 'Continue' : 'Build my first schedule',
                        style: const TextStyle(fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white))))),
        ])),
      ]),
    );
  }
}

class _Page extends StatelessWidget {
  final String  emoji, title, body;
  final String? note;
  const _Page({required this.emoji, required this.title,
      required this.body, required this.note});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 72, height: 72,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
          child: Center(child: Text(emoji,
              style: const TextStyle(fontSize: 34)))),
        const SizedBox(height: 32),
        Text(title, style: const TextStyle(
            fontFamily: 'DMSerifDisplay',
            fontSize: 38, color: Colors.white, height: 1.1,
            letterSpacing: -0.5)),
        const SizedBox(height: 20),
        Text(body, style: TextStyle(fontSize: 16,
            color: Colors.white.withValues(alpha: 0.65), height: 1.7)),
        if (note != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accentLight.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppTheme.accentLight.withValues(alpha: 0.2))),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, size: 14,
                  color: AppTheme.accentLight.withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Expanded(child: Text(note!, style: TextStyle(fontSize: 12,
                  color: AppTheme.accentLight.withValues(alpha: 0.8),
                  height: 1.4))),
            ])),
        ],
      ]),
    );
  }
}

class _OnboardingSkyPainter extends CustomPainter {
  final double t;
  _OnboardingSkyPainter({required this.t});
  static final _rng   = math.Random(99);
  static final _stars = List.generate(60, (_) =>
      Offset(_rng.nextDouble(), _rng.nextDouble()));
  static final _sizes = List.generate(60, (_) =>
      _rng.nextDouble() * 1.4 + 0.4);
  static final _phase = List.generate(60, (_) =>
      _rng.nextDouble() * 2 * math.pi);
  static final _speed = List.generate(60, (_) =>
      0.6 + _rng.nextDouble() * 2.0);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF040D1A), Color(0xFF071428), Color(0xFF0D2040)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    for (var i = 0; i < _stars.length; i++) {
      final twinkle =
          (math.sin(t * 2 * math.pi * _speed[i] + _phase[i]) + 1) / 2;
      canvas.drawCircle(
        Offset(_stars[i].dx * size.width,
            _stars[i].dy * size.height * 0.85),
        _sizes[i],
        Paint()..color =
            Colors.white.withValues(alpha: 0.25 + twinkle * 0.55));
    }
  }

  @override
  bool shouldRepaint(_OnboardingSkyPainter old) => old.t != t;
}