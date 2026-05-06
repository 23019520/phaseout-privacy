// ─────────────────────────────────────────────────────────────
//  lib/screens/dashboard_screen.dart
//
//  FIX #4 — Dashboard overhaul:
//  - Stars flicker in/out individually (random phase per star)
//  - Clouds: larger, overlapping, more vivid, faster movement
//  - Quick actions REMOVED — replaced by smart analytics cards
//  - Analytics: battery prediction, over-limit warning, focus
//    stats, busy day prediction — starts after 1 snapshot
//  - Schedule tiles: bundle-aware icon + colour per type
//  - Screen time cell → taps to Usage screen
//  - Schedules cell → taps to Schedules tab
//  - Sleep timer: standalone prominent card with home-nav on stop
//  - Active BGS pill removed from header (moved to Settings)
//  - Firebase Analytics sign-up card in analytics section
//  - White circles (clouds) overlap more, vivid, animated
// ─────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../db/database_helper.dart';
import '../models/app_usage_model.dart';
import '../models/schedule_model.dart';
import '../services/audio_timer_service.dart';
import '../services/background_service.dart';
import '../models/battery_prediction_result.dart';
import '../services/battery_prediction_service.dart';
import '../services/schedule_action_service.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'audio_timer_screen.dart';
import 'notifications_screen.dart';
import 'schedule_action_overlay.dart';
import 'schedules_screen.dart';
import 'settings_screen.dart';
import 'usage_screen.dart';
import 'focus_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _tab = 0;
  int _unreadCount = 0;

  @override
  void initState() { super.initState(); _loadUnread(); }

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
      body: IndexedStack(
        index: _tab,
        children: [
          _HomeTab(
            onNotificationTap: _openNotifications,
            unreadCount:       _unreadCount,
            onNavigateToUsage:     () => setState(() => _tab = 2),
            onNavigateToSchedules: () => setState(() => _tab = 1),
          ),
          const SchedulesScreen(),
          const UsageScreen(),
          const FocusScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _NavBar(
        current: _tab,
        onTap:   (i) => setState(() => _tab = i),
      ),
    );
  }
}

// ── Bottom nav ────────────────────────────────────────────────
class _NavBar extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;
  const _NavBar({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_rounded,                Icons.home_outlined,           'Home'),
      (Icons.calendar_month_rounded,      Icons.calendar_month_outlined, 'Schedules'),
      (Icons.bar_chart_rounded,           Icons.bar_chart_outlined,      'Usage'),
      (Icons.center_focus_strong_rounded, Icons.center_focus_weak,       'Focus'),
      (Icons.tune_rounded,                Icons.tune_outlined,           'Settings'),
    ];

    return Container(
      height: 72 + MediaQuery.of(context).padding.bottom,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1628),
        border: Border(top: BorderSide(
            color: Colors.white.withValues(alpha: 0.06), width: 0.5)),
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final active = i == current;
          final item   = items[i];
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40, height: 32,
                    decoration: BoxDecoration(
                      color: active
                          ? AppTheme.accentLight.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(active ? item.$1 : item.$2,
                        size: 20,
                        color: active
                            ? AppTheme.accentLight
                            : Colors.white.withValues(alpha: 0.35)),
                  ),
                  const SizedBox(height: 2),
                  Text(item.$3, style: TextStyle(
                      fontSize: 9,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active
                          ? AppTheme.accentLight
                          : Colors.white.withValues(alpha: 0.35),
                      letterSpacing: 0.3)),
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
  final VoidCallback onNavigateToUsage;
  final VoidCallback onNavigateToSchedules;

  const _HomeTab({
    required this.onNotificationTap,
    required this.unreadCount,
    required this.onNavigateToUsage,
    required this.onNavigateToSchedules,
  });

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with TickerProviderStateMixin {
  late final AnimationController _skyCtrl;

  bool                _bgsRunning       = false;
  int                 _screenMinutes    = 0;
  int                 _scheduleCount    = 0;
  String?             _batteryPrediction;
  String?             _timerRemaining;
  List<ScheduleModel> _tonightSchedules = [];
  int                 _overLimitCount   = 0;
  bool                _analyticsReady   = false;

  // Full prediction fields
  String?               _tomorrowWarning;
  PredictionConfidence? _predictionConfidence;
  String?               _formattedDrainRate;
  bool                  _isBusyDay        = false;

  @override
  void initState() {
    super.initState();
    _skyCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 60))
      ..repeat();
    _load();
  }

  @override
  void dispose() { _skyCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final running   = await BackgroundService.isRunning();
      final usage     = await DatabaseHelper.instance
          .getUsageForDate(AppUsageModel.todayString());
      final schedules = await DatabaseHelper.instance.getEnabledSchedules();
      final pred      = await BatteryPredictionService.predictLowBatteryTime();
      final fullPred  = await BatteryPredictionService.fullPrediction();
      final timer     = await AudioTimerService.formattedRemaining();
      final overLimit = await DatabaseHelper.instance.getAppsOverLimit();
      // ML ready after just 1 battery snapshot
      final snapshots = await DatabaseHelper.instance.getBatterySnapshots(days: 1);

      final today   = DateTime.now().weekday;
      final tonight = schedules
          .where((s) => s.daysOfWeek.contains(today))
          .toList()
        ..sort((a, b) => a.triggerTime.hour.compareTo(b.triggerTime.hour));

      if (mounted) {
        setState(() {
          _bgsRunning           = running;
          _screenMinutes        = usage.fold(0, (s, a) => s + a.usageMinutes);
          _scheduleCount        = schedules.length;
          _batteryPrediction    = pred;
          _timerRemaining       = timer == 'No timer' ? null : timer;
          _tonightSchedules     = tonight;
          _overLimitCount       = overLimit.length;
          _analyticsReady       = snapshots.isNotEmpty;
          _tomorrowWarning      = fullPred.tomorrowWarning;
          _predictionConfidence = fullPred.confidence;
          _formattedDrainRate   = fullPred.formattedDrainRate;
          _isBusyDay            = fullPred.isBusyDay;
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
    final result = await ScheduleActionOverlay.show(context, schedule);
    switch (result) {
      case ScheduleOverlayResult.proceed:
        AppLogger.i('HomeTab', 'User approved: ${schedule.name}');
        break;
      case ScheduleOverlayResult.snooze:
        if (schedule.id != null && mounted) {
          final minutes = await _pickSnooze(context);
          if (minutes != null && schedule.id != null) {
            await ScheduleActionService.snooze(schedule.id!, minutes);
          }
        }
        break;
      case ScheduleOverlayResult.skipToday:
        if (schedule.id != null) {
          await ScheduleActionService.skipToday(schedule.id!);
        }
        break;
      case null:
        break;
    }
  }

  Future<int?> _pickSnooze(BuildContext context) async {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Snooze for how long?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 16),
            ...[15, 30, 60, 120].map((m) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(m < 60 ? '$m minutes' : '${m ~/ 60} hour${m > 60 ? 's' : ''}',
                  style: const TextStyle(color: AppTheme.textPrimary)),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textHint),
              onTap: () => Navigator.pop(context, m),
            )),
          ]),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5)  return 'Still up?';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 21) return 'Good evening';
    return 'Time to wind down';
  }

  String _formatScreen() {
    if (_screenMinutes < 60) return '${_screenMinutes}m';
    return '${_screenMinutes ~/ 60}h ${_screenMinutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [

      // Night sky — vivid clouds, flickering stars
      Positioned.fill(
        child: AnimatedBuilder(
          animation: _skyCtrl,
          builder: (_, __) => CustomPaint(
            painter: _NightSkyPainter(t: _skyCtrl.value),
          ),
        ),
      ),

      SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppTheme.accentLight,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [

              // Header — notification bell only (BGS pill removed)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_greeting(), style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.55),
                            letterSpacing: 0.3)),
                        const SizedBox(height: 1),
                        const Text('PhaseOut', style: TextStyle(
                            fontFamily: 'DMSerifDisplay',
                            fontSize: 22, color: Colors.white)),
                      ],
                    )),
                    // Notification bell
                    GestureDetector(
                      onTap: widget.onNotificationTap,
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Stack(alignment: Alignment.center, children: [
                          Icon(
                            widget.unreadCount > 0
                                ? Icons.notifications_rounded
                                : Icons.notifications_none_rounded,
                            size: 20,
                            color: widget.unreadCount > 0
                                ? AppTheme.accentLight
                                : Colors.white.withValues(alpha: 0.5),
                          ),
                          if (widget.unreadCount > 0)
                            Positioned(top: 6, right: 6,
                              child: Container(width: 8, height: 8,
                                decoration: const BoxDecoration(
                                    color: AppTheme.danger,
                                    shape: BoxShape.circle))),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // ── STAT CARDS (clickable) ──────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    // Screen time → taps to Usage
                    Expanded(child: GestureDetector(
                      onTap: widget.onNavigateToUsage,
                      child: _GlassStatCard(
                        value: _screenMinutes > 0 ? _formatScreen() : '—',
                        label: 'Screen time',
                        icon:  Icons.phone_android_rounded,
                        color: AppTheme.tealLight,
                      ),
                    )),
                    const SizedBox(width: 10),
                    // Schedule count → taps to Schedules
                    Expanded(child: GestureDetector(
                      onTap: widget.onNavigateToSchedules,
                      child: _GlassStatCard(
                        value: '$_scheduleCount',
                        label: 'Schedules',
                        icon:  Icons.calendar_month_rounded,
                        color: AppTheme.accentLight,
                      ),
                    )),
                    if (_batteryPrediction != null) ...[
                      const SizedBox(width: 10),
                      Expanded(child: _GlassStatCard(
                        value: _batteryPrediction!,
                        label: 'Low battery',
                        icon:  Icons.battery_3_bar_rounded,
                        color: _isBusyDay ? AppTheme.danger : AppTheme.warning,
                        // Show drain rate as subtitle when available
                        subtitle: _formattedDrainRate,
                        // Badge for prediction confidence
                        badge: (_predictionConfidence != null &&
                            _predictionConfidence != PredictionConfidence.none)
                            ? _confidenceBadgeLabel(_predictionConfidence!)
                            : null,
                        badgeColor: (_predictionConfidence != null &&
                            _predictionConfidence != PredictionConfidence.none)
                            ? _confidenceBadgeColor(_predictionConfidence!)
                            : null,
                      )),
                    ],
                  ]),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // ── SLEEP TIMER — standalone prominent card ─────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _SleepTimerCard(
                    remaining: _timerRemaining,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const AudioTimerScreen()))
                        .then((_) => _load()),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // ── SMART ANALYTICS ─────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionLabel('Insights'),
                      const SizedBox(height: 10),
                      _AnalyticsPanel(
                        batteryPrediction:    _batteryPrediction,
                        tomorrowWarning:      _tomorrowWarning,
                        predictionConfidence: _predictionConfidence,
                        overLimitCount:       _overLimitCount,
                        screenMinutes:        _screenMinutes,
                        analyticsReady:       _analyticsReady,
                        bgsRunning:           _bgsRunning,
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // ── TONIGHT'S SCHEDULES ─────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionLabel("Tonight's schedules"),
                      const SizedBox(height: 10),
                      if (_tonightSchedules.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Column(children: [
                            Icon(Icons.nightlight_round, size: 28,
                                color: Colors.white.withValues(alpha: 0.2)),
                            const SizedBox(height: 8),
                            Text('No schedules tonight',
                                style: TextStyle(fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.45))),
                          ]),
                        )
                      else
                        ..._tonightSchedules.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ScheduleTile(schedule: s),
                        )),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    ]);
  }
}

// ── Confidence badge helpers ──────────────────────────────────
String _confidenceBadgeLabel(PredictionConfidence c) {
  switch (c) {
    case PredictionConfidence.high:   return 'High';
    case PredictionConfidence.medium: return 'Mid';
    case PredictionConfidence.low:    return 'Low';
    case PredictionConfidence.none:   return '';
  }
}

Color _confidenceBadgeColor(PredictionConfidence c) {
  switch (c) {
    case PredictionConfidence.high:   return AppTheme.success;
    case PredictionConfidence.medium: return AppTheme.warning;
    case PredictionConfidence.low:    return AppTheme.danger;
    case PredictionConfidence.none:   return AppTheme.textHint;
  }
}

// ── Sleep timer card ──────────────────────────────────────────
class _SleepTimerCard extends StatelessWidget {
  final String?      remaining;
  final VoidCallback onTap;
  const _SleepTimerCard({required this.remaining, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = remaining != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF60A5FA).withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? const Color(0xFF60A5FA).withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF60A5FA).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.bedtime_rounded,
                color: Color(0xFF60A5FA), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sleep timer',
                  style: TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 3),
              Text(
                active ? 'Active — $remaining left' : 'Stop audio when you fall asleep',
                style: TextStyle(fontSize: 11,
                    color: active
                        ? const Color(0xFF60A5FA)
                        : Colors.white.withValues(alpha: 0.5))),
            ],
          )),
          if (active)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF60A5FA).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(remaining!,
                  style: const TextStyle(fontSize: 11,
                      color: Color(0xFF60A5FA), fontWeight: FontWeight.w600)))
          else
            Icon(Icons.arrow_forward_ios_rounded, size: 12,
                color: Colors.white.withValues(alpha: 0.25)),
        ]),
      ),
    );
  }
}

// ── Analytics panel ───────────────────────────────────────────
class _AnalyticsPanel extends StatelessWidget {
  final String?               batteryPrediction;
  final String?               tomorrowWarning;
  final PredictionConfidence? predictionConfidence;
  final int                   overLimitCount;
  final int                   screenMinutes;
  final bool                  analyticsReady;
  final bool                  bgsRunning;

  const _AnalyticsPanel({
    required this.batteryPrediction,
    required this.tomorrowWarning,
    required this.predictionConfidence,
    required this.overLimitCount,
    required this.screenMinutes,
    required this.analyticsReady,
    required this.bgsRunning,
  });

  List<_InsightItem> _insights() {
    final items = <_InsightItem>[];

    if (!bgsRunning) {
      items.add(const _InsightItem(
        icon:  Icons.warning_amber_rounded,
        color: AppTheme.danger,
        text:  'Background service stopped — schedules won\'t fire.',
      ));
    }

    if (batteryPrediction != null) {
      items.add(_InsightItem(
        icon:  Icons.battery_alert_rounded,
        color: AppTheme.warning,
        text:  'Battery estimated to be low at $batteryPrediction',
      ));
    }

    // Tomorrow warning from fullPrediction
    if (tomorrowWarning != null) {
      items.add(_InsightItem(
        icon:  Icons.calendar_today_rounded,
        color: AppTheme.warning,
        text:  tomorrowWarning!,
      ));
    }

    if (overLimitCount > 0) {
      items.add(_InsightItem(
        icon:  Icons.timer_off_rounded,
        color: AppTheme.danger,
        text:  '$overLimitCount app${overLimitCount > 1 ? "s are" : " is"} over daily limit today',
      ));
    }

    if (screenMinutes > 240) {
      items.add(_InsightItem(
        icon:  Icons.phone_android_rounded,
        color: AppTheme.amber,
        text:  'Over ${screenMinutes ~/ 60}h screen time today',
      ));
    }

    if (analyticsReady && batteryPrediction == null) {
      items.add(const _InsightItem(
        icon:  Icons.check_circle_rounded,
        color: AppTheme.success,
        text:  'Battery is looking good for tonight',
      ));
    }

    if (items.isEmpty) {
      items.add(const _InsightItem(
        icon:  Icons.auto_awesome_rounded,
        color: AppTheme.accentLight,
        text:  'All looking good — PhaseOut has you covered tonight.',
      ));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final insights = _insights();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: List.generate(insights.length, (i) {
          final item = insights[i];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(children: [
                Container(width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9)),
                  child: Icon(item.icon, size: 16, color: item.color)),
                const SizedBox(width: 12),
                Expanded(child: Text(item.text,
                    style: TextStyle(fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.8),
                        height: 1.4))),
              ]),
            ),
            if (i < insights.length - 1)
              Divider(height: 0,
                  color: Colors.white.withValues(alpha: 0.06), indent: 14),
          ]);
        }),
      ),
    );
  }
}

class _InsightItem {
  final IconData icon;
  final Color    color;
  final String   text;
  const _InsightItem({required this.icon, required this.color, required this.text});
}

// ── Schedule tile — bundle-aware ──────────────────────────────
class _ScheduleTile extends StatelessWidget {
  final ScheduleModel schedule;
  const _ScheduleTile({required this.schedule});

  String _fmt() {
    final h  = schedule.triggerTime.hour;
    final m  = schedule.triggerTime.minute.toString().padLeft(2, '0');
    final ap = h >= 12 ? 'PM' : 'AM';
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$h12:$m $ap';
  }

  // Detect bundle type from actions list
  _BundleStyle _style() {
    final a = schedule.actions.toSet();
    if (a.contains(AppConstants.actionStopMedia) &&
        a.contains(AppConstants.actionDimBrightness) &&
        a.contains(AppConstants.actionDoNotDisturb)) {
      return const _BundleStyle(Icons.nightlight_round,
          Color(0xFF60A5FA), 'Sleep mode');
    }
    if (a.contains(AppConstants.actionGoHome) &&
        a.contains(AppConstants.actionDoNotDisturb) &&
        !a.contains(AppConstants.actionStopMedia)) {
      return const _BundleStyle(Icons.center_focus_strong_rounded,
          Color(0xFFFBBF24), 'Focus time');
    }
    if (a.contains(AppConstants.actionDoNotDisturb) && a.length == 1) {
      return const _BundleStyle(Icons.do_not_disturb_rounded,
          Color(0xFFA78BFA), 'Silent hours');
    }
    if (a.contains(AppConstants.actionDimBrightness) && !a.contains(AppConstants.actionDoNotDisturb)) {
      return const _BundleStyle(Icons.battery_saver_rounded,
          Color(0xFF34D399), 'Battery saver');
    }
    if (a.contains(AppConstants.actionStopMedia) && a.length <= 2) {
      return const _BundleStyle(Icons.music_off_rounded,
          Color(0xFFF472B6), 'Stop media');
    }
    return _BundleStyle(Icons.tune_rounded,
        AppTheme.accentLight, schedule.name);
  }

  @override
  Widget build(BuildContext context) {
    final style = _style();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: style.color.withValues(alpha: 0.2), width: 0.5)),
      child: Row(children: [
        Container(width: 40, height: 40,
          decoration: BoxDecoration(
            color: style.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11)),
          child: Icon(style.icon, color: style.color, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(style.label, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 2),
          Text(_fmt(), style: TextStyle(fontSize: 11,
              color: Colors.white.withValues(alpha: 0.45))),
        ])),
        Container(width: 7, height: 7,
          decoration: BoxDecoration(
            color: schedule.enabled
                ? AppTheme.success : Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle)),
      ]),
    );
  }
}

class _BundleStyle {
  final IconData icon; final Color color; final String label;
  const _BundleStyle(this.icon, this.color, this.label);
}

// ── Glass stat card ───────────────────────────────────────────
class _GlassStatCard extends StatelessWidget {
  final String   value, label;
  final IconData icon;
  final Color    color;
  final String?  subtitle;
  final String?  badge;
  final Color?   badgeColor;

  const _GlassStatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.subtitle,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: color.withValues(alpha: 0.8)),
          if (badge != null) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: (badgeColor ?? color).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(badge!,
                  style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: badgeColor ?? color,
                      letterSpacing: 0.2)),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontFamily: 'DMSerifDisplay',
            fontSize: 18, color: color, height: 1)),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 9,
            color: Colors.white.withValues(alpha: 0.45),
            fontWeight: FontWeight.w500, letterSpacing: 0.2)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!,
              style: TextStyle(
                  fontSize: 9,
                  color: color.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w500)),
        ],
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.35), letterSpacing: 1.4));
}

// ── Night sky painter — no clouds, rich flickering stars ──────
class _NightSkyPainter extends CustomPainter {
  final double t;
  _NightSkyPainter({required this.t});

  static final _rng    = math.Random(42);
  static final _stars  = List.generate(120, (_) =>
      Offset(_rng.nextDouble(), _rng.nextDouble()));
  static final _sizes  = List.generate(120, (_) =>
      _rng.nextDouble() * 2.2 + 0.5);
  // Each star has a unique random phase so they all flicker independently
  static final _phase  = List.generate(120, (_) => _rng.nextDouble() * 2 * math.pi);
  static final _speed  = List.generate(120, (_) => 0.8 + _rng.nextDouble() * 2.5);
  // A subset of stars are "bright" — they get a soft cross-glow
  static final _bright = List.generate(120, (i) => i % 7 == 0);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;

    // Sky gradient
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF040D1A), Color(0xFF071428),
                 Color(0xFF0D2040), Color(0xFF122450)],
        stops: [0.0, 0.3, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h)));

    // Blue glow
    canvas.drawCircle(Offset(w * 0.2, h * 0.1), w * 0.6, Paint()
      ..shader = RadialGradient(colors: [
        const Color(0xFF1E40AF).withValues(alpha: 0.14), Colors.transparent,
      ]).createShader(Rect.fromCircle(
          center: Offset(w * 0.2, h * 0.1), radius: w * 0.6)));

    // Stars — each flickers at its own random speed and phase
    for (var i = 0; i < _stars.length; i++) {
      final raw   = (math.sin(t * 2 * math.pi * _speed[i] + _phase[i]) + 1) / 2;
      // Hard blink: stars go fully dark ~20% of the time
      final alpha = raw < 0.2 ? 0.0 : 0.35 + raw * 0.65;
      final pos   = Offset(_stars[i].dx * w, _stars[i].dy * h * 0.70);
      final r     = _sizes[i];

      if (_bright[i] && alpha > 0.4) {
        // Cross-glow: two thin perpendicular lines (horizontal + vertical)
        final glowPaint = Paint()
          ..color       = Colors.white.withValues(alpha: alpha * 0.25)
          ..strokeWidth = r * 0.7
          ..strokeCap   = StrokeCap.round;
        final arm = r * 4.5;
        canvas.drawLine(pos.translate(-arm, 0), pos.translate(arm, 0), glowPaint);
        canvas.drawLine(pos.translate(0, -arm), pos.translate(0,  arm), glowPaint);
        // Slightly larger core for bright stars
        canvas.drawCircle(pos, r * 1.4,
            Paint()..color = Colors.white.withValues(alpha: alpha));
      } else {
        canvas.drawCircle(pos, r,
            Paint()..color = Colors.white.withValues(alpha: alpha));
      }
    }

    // Crescent moon
    final mc = Offset(w * 0.82, h * 0.12);
    canvas.drawCircle(mc, 28, Paint()..color = Colors.white.withValues(alpha: 0.85));
    canvas.drawCircle(mc + const Offset(10, -8), 24,
        Paint()..color = const Color(0xFF040D1A));
  }

  @override
  bool shouldRepaint(_NightSkyPainter old) => old.t != t;
}