// ─────────────────────────────────────────────────────────────
//  lib/screens/dashboard_screen.dart  — PhaseOut v1.0
//
//  CHANGE: Home tab shows a screen intro overlay on first open.
//  This replaces the separate OnboardingScreen entirely.
//  Splash → Dashboard → overlay explains home features.
//
//  The overlay also asks for Notification permission —
//  the one permission needed for basic scheduling to work.
// ─────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app_theme.dart';
import '../db/database_helper.dart';
import '../models/app_usage_model.dart';
import '../models/schedule_model.dart';
import '../services/audio_timer_service.dart';
import '../services/background_service.dart';
import '../services/battery_prediction_service.dart';
import '../services/schedule_action_service.dart';
import '../utils/logger.dart';
import '../widgets/screen_intro_overlay.dart';
import 'audio_timer_screen.dart';
import 'focus_screen.dart';
import 'notifications_screen.dart';
import 'schedule_action_overlay.dart';
import 'schedules_screen.dart';
import 'settings_screen.dart';
import 'usage_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _tab         = 0;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUnread();
  }

  Future<void> _loadUnread() async {
    final events = await DatabaseHelper.instance.getUsageEvents(limit: 20);
    if (mounted) setState(() => _unreadCount = events.length.clamp(0, 9));
  }

  void _openNotifications() {
    setState(() => _unreadCount = 0);
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: IndexedStack(index: _tab, children: [
        _HomeTab(
          onNotificationTap: _openNotifications,
          unreadCount:       _unreadCount,
        ),
        const SchedulesScreen(),
        const UsageScreen(),
        const FocusScreen(),
        const SettingsScreen(),
      ]),
      bottomNavigationBar:
          _NavBar(current: _tab, onTap: (i) => setState(() => _tab = i)),
    );
  }
}

// ── Bottom nav ────────────────────────────────────────────────
class _NavBar extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;
  const _NavBar({required this.current, required this.onTap});

  static const _items = [
    (Icons.home_rounded,                Icons.home_outlined,           'Home'),
    (Icons.calendar_month_rounded,      Icons.calendar_month_outlined, 'Schedules'),
    (Icons.bar_chart_rounded,           Icons.bar_chart_outlined,      'Usage'),
    (Icons.center_focus_strong_rounded, Icons.center_focus_weak,       'Focus'),
    (Icons.tune_rounded,                Icons.tune_outlined,           'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 68 + bottom,
      padding: EdgeInsets.only(bottom: bottom),
      decoration: BoxDecoration(
        color: const Color(0xFF080F1E),
        border: Border(top: BorderSide(
            color: Colors.white.withValues(alpha: 0.07), width: 0.5)),
      ),
      child: Row(
        children: List.generate(_items.length, (i) {
          final active = i == current;
          final item   = _items[i];
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              splashColor:    Colors.transparent,
              highlightColor: Colors.transparent,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 38, height: 30,
                    decoration: BoxDecoration(
                      color: active
                          ? AppTheme.accentLight.withValues(alpha: 0.13)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(active ? item.$1 : item.$2,
                      size: 19,
                      color: active
                          ? AppTheme.accentLight
                          : Colors.white.withValues(alpha: 0.32)),
                  ),
                  const SizedBox(height: 3),
                  Text(item.$3,
                    style: TextStyle(
                      fontSize:   9,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active
                          ? AppTheme.accentLight
                          : Colors.white.withValues(alpha: 0.32),
                      letterSpacing: 0.2,
                    )),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  HOME TAB
// ─────────────────────────────────────────────────────────────
class _HomeTab extends StatefulWidget {
  final VoidCallback onNotificationTap;
  final int          unreadCount;
  const _HomeTab({
    required this.onNotificationTap,
    required this.unreadCount,
  });

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab>
    with TickerProviderStateMixin {

  late final AnimationController _skyCtrl;

  bool                _bgsRunning       = false;
  int                 _screenMinutes    = 0;
  int                 _scheduleCount    = 0;
  String?             _prediction;
  String?             _timerRemaining;
  List<ScheduleModel> _tonightSchedules = [];

  @override
  void initState() {
    super.initState();
    _skyCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 80))
      ..repeat();
    _load();
    // Show home intro overlay on first visit
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _showIntroIfNeeded());
  }

  @override
  void dispose() {
    _skyCtrl.dispose();
    super.dispose();
  }

  // ── Home intro overlay ────────────────────────────────────
  // Triggered once, explains what the home screen does,
  // then asks for notification permission.
  Future<void> _showIntroIfNeeded() async {
    await ScreenIntroOverlay.showIfNeeded(
      context,
      screenKey: 'home_tab',
      title:     'Welcome to PhaseOut',
      subtitle:
          'Your sleep and focus companion. Here\'s what this screen does.',
      features: const [
        ScreenFeature(
          icon:     Icons.nightlight_round,
          color:    AppTheme.accentLight,
          title:    'Tonight\'s schedules',
          subtitle: 'See what bedtime automations fire tonight at a glance',
        ),
        ScreenFeature(
          icon:     Icons.bedtime_rounded,
          color:    Color(0xFF60A5FA),
          title:    'Sleep timer',
          subtitle: 'Start a countdown that stops your music when you fall asleep',
        ),
        ScreenFeature(
          icon:     Icons.center_focus_strong_rounded,
          color:    Color(0xFFFBBF24),
          title:    'Focus session',
          subtitle: 'Block distracting apps with one tap',
        ),
        ScreenFeature(
          icon:     Icons.battery_3_bar_rounded,
          color:    Color(0xFF34D399),
          title:    'Battery prediction',
          subtitle: 'See when your battery will hit 20% based on today\'s usage',
        ),
      ],
      permission: ScreenPermission(
        icon:  Icons.notifications_rounded,
        color: const Color(0xFF60A5FA),
        title: 'Send notifications',
        reason:
            'PhaseOut sends you a bedtime reminder before your schedule fires. '
            'Without this, you won\'t receive wind-down alerts.',
        onGrant: () async {
          await Permission.notification.request();
        },
        checkGranted: () async => Permission.notification.isGranted,
      ),
    );
  }

  Future<void> _load() async {
    try {
      final running   = await BackgroundService.isRunning();
      final usage     = await DatabaseHelper.instance
          .getUsageForDate(AppUsageModel.todayString());
      final schedules = await DatabaseHelper.instance.getEnabledSchedules();
      final pred      = await BatteryPredictionService.predictLowBatteryTime();
      final timer     = await AudioTimerService.formattedRemaining();

      final today   = DateTime.now().weekday;
      final tonight = schedules
          .where((s) => s.daysOfWeek.contains(today))
          .toList()
        ..sort((a, b) => a.triggerTime.hour.compareTo(b.triggerTime.hour));

      if (mounted) {
        setState(() {
          _bgsRunning       = running;
          _screenMinutes    = usage.fold(0, (s, a) => s + a.usageMinutes);
          _scheduleCount    = schedules.length;
          _prediction       = pred;
          _timerRemaining   = timer == 'No timer' ? null : timer;
          _tonightSchedules = tonight;
        });
      }

      _checkSnoozedSchedules(schedules);
    } catch (e) {
      AppLogger.e('HomeTab', 'load failed', e);
    }
  }

  Future<void> _checkSnoozedSchedules(List<ScheduleModel> schedules) async {
    for (final s in schedules) {
      if (s.id == null) continue;
      final expired = await ScheduleActionService.snoozeExpiredNow(s.id!);
      if (expired && mounted) _showOverlay(s);
    }
  }

  Future<void> _showOverlay(ScheduleModel schedule) async {
    if (!mounted) return;
    final response = await ScheduleActionOverlay.show(context, schedule);
    if (response == null) return;
    switch (response.result) {
      case ScheduleOverlayResult.proceed:
        break;
      case ScheduleOverlayResult.snooze:
        if (schedule.id != null) {
          await ScheduleActionService.snooze(
              schedule.id!, response.snoozeMinutes ?? 30);
        }
        break;
      case ScheduleOverlayResult.skipToday:
        if (schedule.id != null) {
          await ScheduleActionService.skipToday(schedule.id!);
        }
        break;
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5)  return 'Still up?';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 21) return 'Good evening';
    return 'Time to wind down';
  }

  String _fmtScreen() {
    if (_screenMinutes < 60) return '${_screenMinutes}m';
    return '${_screenMinutes ~/ 60}h ${_screenMinutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [

      // Night sky
      Positioned.fill(
        child: AnimatedBuilder(
          animation: _skyCtrl,
          builder: (_, __) =>
              CustomPaint(painter: _SkyPainter(t: _skyCtrl.value)),
        ),
      ),

      SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppTheme.accentLight,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [

              // ── Header ──────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_greeting(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.5),
                            letterSpacing: 0.3,
                          )),
                        const SizedBox(height: 2),
                        const Text('PhaseOut',
                          style: TextStyle(
                            fontFamily:    'DMSerifDisplay',
                            fontSize:      24,
                            color:         Colors.white,
                            letterSpacing: 0.2,
                          )),
                      ],
                    )),

                    // Bell
                    _BellButton(
                      count: widget.unreadCount,
                      onTap: widget.onNotificationTap,
                    ),
                    const SizedBox(width: 8),

                    // BGS status
                    _StatusPill(active: _bgsRunning),
                  ]),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // ── Stat cards ───────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    _StatCard(
                      value: _screenMinutes > 0 ? _fmtScreen() : '—',
                      label: 'Screen today',
                      icon:  Icons.phone_android_rounded,
                      color: AppTheme.tealLight,
                    ),
                    const SizedBox(width: 10),
                    _StatCard(
                      value: '$_scheduleCount',
                      label: 'Schedules',
                      icon:  Icons.calendar_month_rounded,
                      color: AppTheme.accentLight,
                    ),
                    if (_prediction != null) ...[
                      const SizedBox(width: 10),
                      _StatCard(
                        value: _prediction!,
                        label: 'Battery low',
                        icon:  Icons.battery_3_bar_rounded,
                        color: AppTheme.warning,
                      ),
                    ],
                  ]),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 28)),

              // ── Quick actions ────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Label('Quick actions'),
                      const SizedBox(height: 12),
                      _ActionCard(
                        icon:  Icons.bedtime_rounded,
                        color: const Color(0xFF60A5FA),
                        title: 'Sleep timer',
                        sub: _timerRemaining != null
                            ? 'Active — $_timerRemaining remaining'
                            : 'Auto-stop audio when you fall asleep',
                        badge: _timerRemaining,
                        onTap: () => Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) => const AudioTimerScreen())),
                      ),
                      const SizedBox(height: 10),
                      _ActionCard(
                        icon:  Icons.center_focus_strong_rounded,
                        color: const Color(0xFFFBBF24),
                        title: 'Focus session',
                        sub:   'Block distracting apps now',
                        onTap: () => Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) => const FocusScreen())),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Tonight ──────────────────────────────────
              if (_tonightSchedules.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Label('Tonight'),
                        const SizedBox(height: 12),
                        ..._tonightSchedules.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ScheduleRow(schedule: s),
                        )),
                      ],
                    ),
                  ),
                ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
//  COMPONENTS
// ─────────────────────────────────────────────────────────────

class _BellButton extends StatelessWidget {
  final int count; final VoidCallback onTap;
  const _BellButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
      child: Stack(alignment: Alignment.center, children: [
        Icon(
          count > 0
              ? Icons.notifications_rounded
              : Icons.notifications_none_rounded,
          size: 20,
          color: count > 0
              ? AppTheme.accentLight
              : Colors.white.withValues(alpha: 0.45)),
        if (count > 0)
          Positioned(top: 5, right: 5,
            child: Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                color: AppTheme.danger,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.navy, width: 1.5)),
              child: Center(child: Text(
                count > 9 ? '9+' : '$count',
                style: const TextStyle(fontSize: 8,
                    fontWeight: FontWeight.w700, color: Colors.white))))),
      ]),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  final bool active;
  const _StatusPill({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.success : AppTheme.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 5, height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(active ? 'Active' : 'Off',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value, label; final IconData icon; final Color color;
  const _StatCard({required this.value, required this.label,
      required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09), width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: color.withValues(alpha: 0.8)),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontFamily: 'DMSerifDisplay',
            fontSize: 20, color: color, height: 1)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 9,
            color: Colors.white.withValues(alpha: 0.4),
            fontWeight: FontWeight.w500, letterSpacing: 0.2)),
      ]),
    ),
  );
}

class _ActionCard extends StatelessWidget {
  final IconData icon; final Color color;
  final String title, sub; final String? badge;
  final VoidCallback onTap;
  const _ActionCard({required this.icon, required this.color,
      required this.title, required this.sub,
      required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
        child: Row(children: [
          Container(width: 44, height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: color, size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14,
                fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 3),
            Text(sub, style: TextStyle(fontSize: 12,
                color: Colors.white.withValues(alpha: 0.48))),
          ])),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99)),
              child: Text(badge!, style: TextStyle(fontSize: 10,
                  color: color, fontWeight: FontWeight.w600)))
          else
            Icon(Icons.chevron_right_rounded, size: 16,
                color: Colors.white.withValues(alpha: 0.22)),
        ]),
      ),
    ),
  );
}

class _ScheduleRow extends StatelessWidget {
  final ScheduleModel schedule;
  const _ScheduleRow({required this.schedule});

  String _fmt() {
    final h   = schedule.triggerTime.hour;
    final m   = schedule.triggerTime.minute.toString().padLeft(2, '0');
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$h12:$m ${h >= 12 ? "PM" : "AM"}';
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.09), width: 0.5)),
    child: Row(children: [
      Container(width: 38, height: 38,
        decoration: BoxDecoration(
            color: AppTheme.accentLight.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.nightlight_round,
            color: AppTheme.accentLight, size: 18)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(schedule.name, style: const TextStyle(fontSize: 13,
            fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 2),
        Text(_fmt(), style: TextStyle(fontSize: 11,
            color: Colors.white.withValues(alpha: 0.42))),
      ])),
      Container(width: 6, height: 6,
        decoration: BoxDecoration(
          color: schedule.enabled
              ? AppTheme.success
              : Colors.white.withValues(alpha: 0.2),
          shape: BoxShape.circle)),
    ]),
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.35), letterSpacing: 1.4));
}

// ── Sky painter ───────────────────────────────────────────────
class _SkyPainter extends CustomPainter {
  final double t;
  _SkyPainter({required this.t});

  static final _rng   = math.Random(42);
  static final _stars = List.generate(80, (_) => Offset(_rng.nextDouble(), _rng.nextDouble()));
  static final _sizes = List.generate(80, (_) => _rng.nextDouble() * 1.5 + 0.5);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF040D1A), Color(0xFF071428), Color(0xFF0D2040), Color(0xFF122450)],
        stops: [0.0, 0.3, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h)));

    canvas.drawCircle(Offset(w*0.2, h*0.1), w*0.6, Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFF1E40AF).withValues(alpha: 0.12), Colors.transparent,
      ]).createShader(Rect.fromCircle(center: Offset(w*0.2, h*0.1), radius: w*0.6)));

    for (var i = 0; i < _stars.length; i++) {
      final tw = (math.sin(t * 2 * math.pi * (1 + i * 0.07) + i) + 1) / 2;
      canvas.drawCircle(Offset(_stars[i].dx * w, _stars[i].dy * h * 0.65), _sizes[i],
          Paint()..color = Colors.white.withValues(alpha: 0.25 + tw * 0.65));
    }

    final mc = Offset(w * 0.84, h * 0.11);
    canvas.drawCircle(mc, 26, Paint()..color = Colors.white.withValues(alpha: 0.88));
    canvas.drawCircle(mc + const Offset(9, -7), 22, Paint()..color = const Color(0xFF040D1A));

    void cloud(Offset c, double s, double a) {
      final p = Paint()..color = Colors.white.withValues(alpha: a);
      for (final b in [Offset.zero, Offset(28*s,-8*s), Offset(56*s,-2*s),
                        Offset(84*s,-7*s), Offset(42*s,-20*s)]) {
        canvas.drawCircle(c + b, 22 * s, p);
      }
    }
    cloud(Offset(((t*0.04)%1.3)*(w+200)-100,    h*0.74), 1.0, 0.06);
    cloud(Offset(((t*0.025+0.5)%1.3)*(w+200)-100, h*0.82), 0.85, 0.05);
    cloud(Offset(((t*0.035+0.8)%1.3)*(w+200)-100, h*0.88), 1.2, 0.04);
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.t != t;
}