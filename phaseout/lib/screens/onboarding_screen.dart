// ─────────────────────────────────────────────────────────────
//  lib/screens/onboarding_screen.dart  — PhaseOut v1.0 final
//
//  3 pages. No forced schedule creation. Permissions asked
//  on page 3 in a single clear flow (notifications only —
//  the minimum needed for the app to work on day 1).
//
//  Page 1 — What PhaseOut does (warm, human, not technical)
//  Page 2 — How it works tonight (set expectations)
//  Page 3 — One permission, then in you go
// ─────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../utils/constants.dart';
import 'dashboard_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {

  final _ctrl = PageController();
  int  _page  = 0;

  late final AnimationController _skyCtrl;
  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fade;
  late final Animation<Offset>   _slide;

  @override
  void initState() {
    super.initState();
    _skyCtrl  = AnimationController(vsync: this,
        duration: const Duration(seconds: 60))..repeat();
    _fadeCtrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 420))..forward();
    _fade     = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
    _slide    = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _skyCtrl.dispose(); _fadeCtrl.dispose(); _ctrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < 2) {
      _fadeCtrl.forward(from: 0);
      _ctrl.nextPage(
          duration: const Duration(milliseconds: 340), curve: Curves.easeOut);
      setState(() => _page++);
    }
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefOnboardingDone, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF040D1A),
      body: Stack(children: [

        // Star background
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _skyCtrl,
            builder: (_, __) => CustomPaint(painter: _Sky(t: _skyCtrl.value)),
          ),
        ),

        // Pages
        PageView(
          controller: _ctrl,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _Page1(fade: _fade, slide: _slide, onNext: _next),
            _Page2(fade: _fade, slide: _slide, onNext: _next),
            _Page3(fade: _fade, slide: _slide, onFinish: _finish),
          ],
        ),

        // Dots
        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 28,
          left: 0, right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _page == i ? 20 : 6, height: 6,
              decoration: BoxDecoration(
                color: _page == i
                    ? AppTheme.accentLight
                    : Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(3)),
            )),
          ),
        ),
      ]),
    );
  }
}

// ── Page 1: What it is ───────────────────────────────────────
class _Page1 extends StatelessWidget {
  final Animation<double> fade;
  final Animation<Offset>  slide;
  final VoidCallback onNext;
  const _Page1({required this.fade, required this.slide, required this.onNext});

  @override
  Widget build(BuildContext context) => _PageShell(
    fade: fade, slide: slide,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Icon
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
        child: const Icon(Icons.nightlight_round,
            color: Color(0xFF93C5FD), size: 30)),
      const SizedBox(height: 28),

      const Text('Your phone.\nYour rules.',
        style: TextStyle(fontFamily: 'DMSerifDisplay',
            fontSize: 36, color: Colors.white, height: 1.18)),
      const SizedBox(height: 16),

      Text(
        "PhaseOut sits quietly in the background and automates your bedtime — stopping music, dimming the screen, silencing your phone — at whatever time you choose.",
        style: TextStyle(fontSize: 15,
            color: Colors.white.withValues(alpha: 0.55), height: 1.65)),
      const SizedBox(height: 28),

      // Feature pills
      Wrap(spacing: 8, runSpacing: 8, children: [
        _Pill(Icons.music_off_rounded,       'Stops media'),
        _Pill(Icons.do_not_disturb_rounded,  'Do Not Disturb'),
        _Pill(Icons.brightness_2_rounded,    'Dims screen'),
        _Pill(Icons.alarm_rounded,           'Morning alarm'),
        _Pill(Icons.bar_chart_rounded,       'Usage limits'),
        _Pill(Icons.lock_rounded,            'Focus mode'),
      ]),

      const Spacer(),
      _Btn(label: 'Show me how', onTap: onNext),
    ]),
  );
}

// ── Page 2: How it works ──────────────────────────────────────
class _Page2 extends StatelessWidget {
  final Animation<double> fade;
  final Animation<Offset>  slide;
  final VoidCallback onNext;
  const _Page2({required this.fade, required this.slide, required this.onNext});

  @override
  Widget build(BuildContext context) => _PageShell(
    fade: fade, slide: slide,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF0D9488).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: const Color(0xFF0D9488).withValues(alpha: 0.28))),
        child: const Icon(Icons.schedule_rounded,
            color: Color(0xFF5EEAD4), size: 30)),
      const SizedBox(height: 28),

      const Text('Set it once.\nIt works every night.',
        style: TextStyle(fontFamily: 'DMSerifDisplay',
            fontSize: 36, color: Colors.white, height: 1.18)),
      const SizedBox(height: 16),

      Text(
        "Create a bedtime schedule — say 11 PM — and PhaseOut fires automatically, every night you choose, even if the app is fully closed.",
        style: TextStyle(fontSize: 15,
            color: Colors.white.withValues(alpha: 0.55), height: 1.65)),
      const SizedBox(height: 24),

      // How-it-works cards
      _InfoRow(Icons.notifications_rounded,
          '30 minutes before', 'You get a heads-up so you can wrap up'),
      const SizedBox(height: 12),
      _InfoRow(Icons.music_off_rounded,
          'At bedtime', 'Audio stops, DND kicks in, screen dims'),
      const SizedBox(height: 12),
      _InfoRow(Icons.alarm_rounded,
          'In the morning', 'An alarm wakes you and restores all your settings'),

      const Spacer(),
      _Btn(label: 'One last thing →', onTap: onNext),
    ]),
  );
}

// ── Page 3: Notifications permission ─────────────────────────
class _Page3 extends StatefulWidget {
  final Animation<double> fade;
  final Animation<Offset>  slide;
  final VoidCallback onFinish;
  const _Page3({required this.fade, required this.slide,
      required this.onFinish});
  @override State<_Page3> createState() => _Page3State();
}

class _Page3State extends State<_Page3> {
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final g = await Permission.notification.isGranted;
    if (mounted) setState(() => _granted = g);
  }

  Future<void> _grant() async {
    final s = await Permission.notification.request();
    if (mounted) setState(() => _granted = s.isGranted);
  }

  @override
  Widget build(BuildContext context) => _PageShell(
    fade: widget.fade, slide: widget.slide,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF1E40AF).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.28))),
        child: const Icon(Icons.notifications_rounded,
            color: Color(0xFF93C5FD), size: 30)),
      const SizedBox(height: 28),

      const Text('One thing\nbefore you go.',
        style: TextStyle(fontFamily: 'DMSerifDisplay',
            fontSize: 36, color: Colors.white, height: 1.18)),
      const SizedBox(height: 16),

      Text(
        "PhaseOut needs to send you notifications — that's how your bedtime reminder reaches you. We ask for nothing else right now.",
        style: TextStyle(fontSize: 15,
            color: Colors.white.withValues(alpha: 0.55), height: 1.65)),
      const SizedBox(height: 8),
      Text(
        "Other permissions (media control, usage access) appear the first time you use those features — not all at once.",
        style: TextStyle(fontSize: 13,
            color: Colors.white.withValues(alpha: 0.35), height: 1.55)),
      const SizedBox(height: 28),

      // Permission tile
      AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _granted
              ? AppTheme.success.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _granted
              ? AppTheme.success.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1))),
        child: Row(children: [
          Icon(Icons.notifications_rounded, size: 22,
              color: _granted ? AppTheme.success : const Color(0xFF93C5FD)),
          const SizedBox(width: 14),
          const Expanded(child: Text('Send notifications',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                color: Colors.white))),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _granted
                ? Container(
                    key: const ValueKey('ok'),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99)),
                    child: const Text('Granted',
                      style: TextStyle(fontSize: 11,
                          color: AppTheme.success,
                          fontWeight: FontWeight.w600)))
                : GestureDetector(
                    key: const ValueKey('allow'),
                    onTap: _grant,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppTheme.accentLight.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                            color: AppTheme.accentLight.withValues(alpha: 0.4))),
                      child: const Text('Allow',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accentLight)))),
          ),
        ]),
      ),

      const Spacer(),

      _Btn(
        label: _granted ? "Let's go →" : 'Continue',
        onTap: widget.onFinish,
      ),

      if (!_granted) ...[
        const SizedBox(height: 12),
        Center(child: Text(
          'You can grant this later in Settings',
          style: TextStyle(fontSize: 12,
              color: Colors.white.withValues(alpha: 0.28)))),
      ],
    ]),
  );
}

// ── Shared ────────────────────────────────────────────────────

class _PageShell extends StatelessWidget {
  final Animation<double> fade;
  final Animation<Offset>  slide;
  final Widget child;
  const _PageShell({required this.fade, required this.slide,
      required this.child});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 52, 26, 88),
          child: child,
        ),
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  final IconData icon; final String label;
  const _Pill(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: AppTheme.accentLight),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 12,
          color: Colors.white.withValues(alpha: 0.68))),
    ]),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon; final String label, sub;
  const _InfoRow(this.icon, this.label, this.sub);
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: AppTheme.accentLight.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: AppTheme.accentLight)),
      const SizedBox(width: 14),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 13,
            fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 2),
        Text(sub, style: TextStyle(fontSize: 12,
            color: Colors.white.withValues(alpha: 0.48), height: 1.45)),
      ])),
    ],
  );
}

class _Btn extends StatelessWidget {
  final String label; final VoidCallback onTap;
  const _Btn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppTheme.accentLight.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppTheme.accentLight.withValues(alpha: 0.45))),
          child: Text(label, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.accentLight)),
        ),
      ),
    ),
  );
}

class _Sky extends CustomPainter {
  final double t;
  _Sky({required this.t});
  static final _rng   = math.Random(42);
  static final _stars = List.generate(55,
      (_) => Offset(_rng.nextDouble(), _rng.nextDouble() * 0.7));
  static final _sizes = List.generate(55,
      (_) => _rng.nextDouble() * 1.4 + 0.4);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF020810), Color(0xFF071428), Color(0xFF0D2040)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    for (var i = 0; i < _stars.length; i++) {
      final tw = (math.sin(t * 2 * math.pi * (1 + i * 0.1) + i) + 1) / 2;
      canvas.drawCircle(
        Offset(_stars[i].dx * size.width, _stars[i].dy * size.height),
        _sizes[i],
        Paint()..color = Colors.white.withValues(alpha: 0.18 + tw * 0.62));
    }
  }
  @override bool shouldRepaint(_Sky old) => old.t != t;
}