// ─────────────────────────────────────────────────────────────
//  lib/screens/usage_screen.dart
//  PhaseOut — Daily usage dashboard (redesign v3)
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../channels/usage_channel.dart';
import '../db/database_helper.dart';
import '../models/app_usage_model.dart';
import '../services/audio_timer_service.dart';
import '../services/battery_prediction_service.dart';
import '../services/usage_monitor_service.dart';

const _kSystemNoise = <String>{
  'android', 'com.android.systemui', 'com.android.phone',
  'com.google.android.gms', 'com.google.android.gsf',
  'com.android.launcher', 'com.android.launcher3',
  'com.samsung.android.launcher', 'com.google.android.apps.nexuslauncher',
  'com.miui.home', 'com.oneplus.launcher',
  'com.android.inputmethod.latin', 'com.samsung.android.inputmethod',
  'com.google.android.inputmethod.latin', 'com.android.providers.calendar',
  'com.android.providers.media', 'com.android.server.telecom',
  'com.android.keyguard', 'com.android.permissioncontroller',
};

bool _isSystemNoise(String pkg) =>
    _kSystemNoise.contains(pkg) ||
    pkg.startsWith('com.android.server') ||
    pkg.startsWith('com.google.android.gms');

enum _ScreenState { checkingPermission, needsPermission, ready }

// ─────────────────────────────────────────────────────────────
//  UsageScreen
// ─────────────────────────────────────────────────────────────

class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> with WidgetsBindingObserver {
  _ScreenState        _state         = _ScreenState.checkingPermission;
  List<AppUsageModel> _usage         = [];
  bool                _syncing       = false;
  String              _totalLabel    = '0m';
  bool                _dialogShowing = false;

  int     _overLimitCount    = 0;
  String? _batteryPrediction;
  String? _timerRemaining;
  int     _avgMinutes        = 130;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_state == _ScreenState.needsPermission || _state == _ScreenState.ready)) {
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    setState(() => _state = _ScreenState.checkingPermission);
    unawaited(UsageChannel.getAllInstalledApps());
    final granted = await UsageChannel.hasUsagePermission();
    if (!mounted) return;
    if (!granted) {
      setState(() => _state = _ScreenState.needsPermission);
      if (!_dialogShowing) {
        _dialogShowing = true;
        await _showPermissionDialog();
        _dialogShowing = false;
      }
      return;
    }
    await _syncAndLoad();
  }

  Future<void> _syncAndLoad() async {
    if (!mounted) return;
    setState(() => _syncing = true);
    try {
      await UsageMonitorService.syncFromUI();
      await _loadFromDb();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _loadFromDb() async {
    if (!mounted) return;
    final raw = await DatabaseHelper.instance
        .getUsageForDate(AppUsageModel.todayString());

    final needsLabel  = <AppUsageModel>[];
    final passthrough = <AppUsageModel>[];

    for (final app in raw) {
      if (_isSystemNoise(app.packageName)) continue;
      if (app.usageMinutes <= 0) continue;
      final hasLabel = app.appLabel.isNotEmpty && app.appLabel != app.packageName;
      if (hasLabel) { passthrough.add(app); } else { needsLabel.add(app); }
    }

    final resolvedLabels = await Future.wait(
      needsLabel.map((app) => UsageChannel.getAppLabel(app.packageName)),
    );

    for (var i = 0; i < needsLabel.length; i++) {
      final label = resolvedLabels[i];
      if (label != needsLabel[i].packageName) {
        unawaited(DatabaseHelper.instance.insertOrUpdateUsage(
          needsLabel[i].copyWith(appLabel: label),
        ));
      }
    }

    final resolved = [
      ...passthrough,
      ...List.generate(needsLabel.length,
          (i) => needsLabel[i].copyWith(appLabel: resolvedLabels[i])),
    ]..sort((a, b) => b.usageMinutes.compareTo(a.usageMinutes));

    final total     = resolved.fold(0, (s, a) => s + a.usageMinutes);
    final overLimit = resolved.where((a) => a.isOverLimit).length;

    final battery = await BatteryPredictionService.predictLowBatteryTime();
    final timer   = await AudioTimerService.formattedRemaining();

    if (mounted) {
      setState(() {
        _usage             = resolved;
        _totalLabel        = AppUsageModel.formatMinutes(total);
        _state             = _ScreenState.ready;
        _overLimitCount    = overLimit;
        _batteryPrediction = battery;
        _timerRemaining    = (timer == 'No timer') ? null : timer;
        _avgMinutes        = 130;
      });
    }
  }

  Future<void> _showPermissionDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PermissionDialog(
        onGrant: () async {
          Navigator.pop(ctx);
          await UsageChannel.openUsageSettings();
        },
        onDismiss: () => Navigator.pop(ctx),
      ),
    );
  }

  Future<void> _showLimitDialog(AppUsageModel app) async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LimitSheet(app: app),
    );
    if (result == null || !mounted) return;
    await UsageMonitorService.setLimit(app.packageName, result == -1 ? 0 : result);
    await _loadFromDb();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: switch (_state) {
        _ScreenState.checkingPermission => const _LoadingBody(),
        _ScreenState.needsPermission    => _NoPermissionBody(onRetry: _bootstrap),
        _ScreenState.ready              => _ReadyBody(
            usage:             _usage,
            totalLabel:        _totalLabel,
            syncing:           _syncing,
            overLimitCount:    _overLimitCount,
            batteryPrediction: _batteryPrediction,
            timerRemaining:    _timerRemaining,
            avgMinutes:        _avgMinutes,
            onRefresh:         _syncAndLoad,
            onSetLimit:        _showLimitDialog,
          ),
      },
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    title: const Text('Today'),
    actions: [
      if (_state == _ScreenState.ready)
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _syncing
                ? const SizedBox(
                    key: ValueKey('spinner'), width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.textHint),
                  )
                : IconButton(
                    key: const ValueKey('sync'),
                    icon: const Icon(Icons.sync_rounded, size: 20),
                    tooltip: 'Sync now',
                    onPressed: _syncAndLoad,
                  ),
          ),
        ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────
//  Loading body
// ─────────────────────────────────────────────────────────────

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(color: AppTheme.accentLight, strokeWidth: 2),
  );
}

// ─────────────────────────────────────────────────────────────
//  No-permission body
// ─────────────────────────────────────────────────────────────

class _NoPermissionBody extends StatelessWidget {
  final VoidCallback onRetry;
  const _NoPermissionBody({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.bar_chart_rounded, size: 34, color: AppTheme.textHint),
        ),
        const SizedBox(height: 24),
        const Text('Usage access needed',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const SizedBox(height: 10),
        const Text(
          'Grant Usage Access so PhaseOut can track your screen time and enforce your daily limits.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppTheme.textSecond, height: 1.6),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.lock_open_rounded, size: 16),
            label: const Text('Grant access'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
//  Ready body
// ─────────────────────────────────────────────────────────────

class _ReadyBody extends StatelessWidget {
  final List<AppUsageModel>                  usage;
  final String                               totalLabel;
  final bool                                 syncing;
  final int                                  overLimitCount;
  final String?                              batteryPrediction;
  final String?                              timerRemaining;
  final int                                  avgMinutes;
  final Future<void> Function()              onRefresh;
  final Future<void> Function(AppUsageModel) onSetLimit;

  const _ReadyBody({
    required this.usage,
    required this.totalLabel,
    required this.syncing,
    required this.overLimitCount,
    required this.batteryPrediction,
    required this.timerRemaining,
    required this.avgMinutes,
    required this.onRefresh,
    required this.onSetLimit,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    if (usage.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wb_sunny_outlined, size: 40, color: AppTheme.textHint),
          SizedBox(height: 16),
          Text('No usage recorded yet today',
              style: TextStyle(color: AppTheme.textSecond, fontSize: 14)),
          SizedBox(height: 8),
          Text('Pull down to refresh',
              style: TextStyle(color: AppTheme.textHint, fontSize: 12)),
        ]),
      );
    }

    final heroApp   = usage.first;
    final otherApps = usage.length > 1 ? usage.sublist(1) : <AppUsageModel>[];
    final totalMins = usage.fold(0, (s, a) => s + a.usageMinutes);
    final deltaMins = totalMins - avgMinutes;

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.accent,
      backgroundColor: AppTheme.surface,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [

          // Analytics strip
          // FIX 1: was topPad + 64, which overshot the AppBar by ~56px.
          // topPad + 8 places content just below the AppBar with a small breath.
          SliverPadding(
            padding: EdgeInsets.only(top: topPad + 8),
            sliver: SliverToBoxAdapter(
              child: _AnalyticsStrip(
                overLimitCount:    overLimitCount,
                batteryPrediction: batteryPrediction,
                timerRemaining:    timerRemaining,
                totalMinutes:      totalMins,
                avgMinutes:        avgMinutes,
              ),
            ),
          ),

          // Hero total card
          SliverToBoxAdapter(
            child: _HeroCard(
              totalLabel:     totalLabel,
              appCount:       usage.length,
              overLimitCount: overLimitCount,
              totalMinutes:   totalMins,
              avgMinutes:     avgMinutes,
              deltaMins:      deltaMins,
            ),
          ),

          // Most used label
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 28, 20, 10),
              child: _SectionLabel(title: 'Most used'),
            ),
          ),

          // Hero app card (stacked asymmetric)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _HeroAppCard(
                app:       heroApp,
                totalMins: totalMins,
                onTap:     () => onSetLimit(heroApp),
              ),
            ),
          ),

          // All apps slat list
          if (otherApps.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
                child: _SectionLabel(
                  title: 'All apps',
                  trailing: '${otherApps.length} more',
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SlatContainer(apps: otherApps, onSetLimit: onSetLimit),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Analytics strip
//  Chip visual weight: danger (filled border) > warning (semi) > ok (no border)
// ─────────────────────────────────────────────────────────────

enum _ChipStyle { danger, warning, ok }

class _ChipData {
  final IconData   icon;
  final String     label;
  final _ChipStyle style;
  const _ChipData({required this.icon, required this.label, required this.style});
}

class _AnalyticsStrip extends StatelessWidget {
  final int     overLimitCount;
  final String? batteryPrediction;
  final String? timerRemaining;
  final int     totalMinutes;
  final int     avgMinutes;

  const _AnalyticsStrip({
    required this.overLimitCount,
    required this.batteryPrediction,
    required this.timerRemaining,
    required this.totalMinutes,
    required this.avgMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <_ChipData>[];

    if (overLimitCount > 0) {
      chips.add(_ChipData(
        icon:  Icons.timer_off_rounded,
        label: '$overLimitCount app${overLimitCount > 1 ? 's' : ''} over limit',
        style: _ChipStyle.danger,
      ));
    }

    if (batteryPrediction != null) {
      chips.add(_ChipData(
        icon:  Icons.battery_2_bar_rounded,
        label: 'Low battery ~$batteryPrediction',
        style: _ChipStyle.warning,
      ));
    }

    final delta = totalMinutes - avgMinutes;
    if (delta > 15) {
      chips.add(_ChipData(
        icon:  Icons.local_fire_department_rounded,
        label: '${AppUsageModel.formatMinutes(delta)} above avg',
        style: _ChipStyle.warning,
      ));
    } else if (delta < -15) {
      chips.add(_ChipData(
        icon:  Icons.thumb_up_rounded,
        label: '${AppUsageModel.formatMinutes(-delta)} below avg',
        style: _ChipStyle.ok,
      ));
    }

    if (timerRemaining != null) {
      chips.add(_ChipData(
        icon:  Icons.bedtime_rounded,
        label: 'Sleep timer: $timerRemaining',
        style: _ChipStyle.ok,
      ));
    }

    if (overLimitCount == 0 && batteryPrediction == null) {
      chips.add(const _ChipData(
        icon:  Icons.check_circle_rounded,
        label: 'All on track today',
        style: _ChipStyle.ok,
      ));
    }

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _AnalyticsChip(data: chips[i]),
      ),
    );
  }
}

class _AnalyticsChip extends StatelessWidget {
  final _ChipData data;
  const _AnalyticsChip({required this.data});

  @override
  Widget build(BuildContext context) {
    final Color bg, fg;
    final BoxBorder? border;

    switch (data.style) {
      case _ChipStyle.danger:
        bg     = AppTheme.danger.withValues(alpha: 0.16);
        fg     = AppTheme.danger;
        border = Border.all(color: AppTheme.danger.withValues(alpha: 0.40), width: 0.8);
      case _ChipStyle.warning:
        bg     = AppTheme.warning.withValues(alpha: 0.11);
        fg     = AppTheme.warning;
        border = Border.all(color: AppTheme.warning.withValues(alpha: 0.28), width: 0.5);
      case _ChipStyle.ok:
        bg     = AppTheme.success.withValues(alpha: 0.07);
        fg     = AppTheme.success;
        border = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(color: bg, border: border, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(data.icon, size: 12, color: fg),
        const SizedBox(width: 5),
        Text(
          data.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: fg.withValues(alpha: data.style == _ChipStyle.ok ? 0.75 : 0.95),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Section label
// ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String  title;
  final String? trailing;
  const _SectionLabel({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) => Row(children: [
    Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 10, fontWeight: FontWeight.w700,
        color: AppTheme.textHint, letterSpacing: 1.4,
      ),
    ),
    const Spacer(),
    if (trailing != null)
      Text(trailing!, style: const TextStyle(fontSize: 11, color: AppTheme.textHint)),
  ]);
}

// ─────────────────────────────────────────────────────────────
//  Hero total card — no border, tonal surface
// ─────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final String totalLabel;
  final int    appCount;
  final int    overLimitCount;
  final int    totalMinutes;
  final int    avgMinutes;
  final int    deltaMins;

  const _HeroCard({
    required this.totalLabel,
    required this.appCount,
    required this.overLimitCount,
    required this.totalMinutes,
    required this.avgMinutes,
    required this.deltaMins,
  });

  @override
  Widget build(BuildContext context) {
    final now         = DateTime.now();
    final minutesElap = now.hour * 60 + now.minute;
    final dayProgress = (minutesElap / (24 * 60)).clamp(0.0, 1.0);

    final deltaAbs    = AppUsageModel.formatMinutes(deltaMins.abs());
    final deltaColor  = deltaMins > 15
        ? AppTheme.danger
        : deltaMins < -15 ? AppTheme.success : AppTheme.textSecond;
    final deltaPrefix = deltaMins > 15 ? '+' : deltaMins < -15 ? '−' : '~';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Screen time today',
                    style: TextStyle(fontSize: 11, color: AppTheme.textHint, letterSpacing: 0.2)),
                const SizedBox(height: 5),
                Text(totalLabel,
                    style: const TextStyle(
                      fontFamily: 'DMSerifDisplay', fontSize: 40,
                      color: AppTheme.textPrimary, height: 1.05,
                    )),
              ]),
            ),
            // FIX 2: replaced the arc CustomPainter clock with a clean pill —
            // current hour label (e.g. "9AM") above a slim progress bar that
            // echoes the day-progress bar already in this card. Simpler, more
            // readable, and visually consistent.
            _DayProgressPill(progress: dayProgress),
          ]),

          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: dayProgress, minHeight: 3,
              backgroundColor: AppTheme.surface2,
              valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
            ),
          ),
          const SizedBox(height: 5),
          Row(children: [
            Text(_hhmm(now),
                style: const TextStyle(fontSize: 10, color: AppTheme.textHint)),
            const Spacer(),
            Text('${(dayProgress * 100).round()}% of day',
                style: const TextStyle(fontSize: 10, color: AppTheme.textHint)),
          ]),

          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0x0F63A8D2)),
          const SizedBox(height: 14),

          Row(children: [
            _MiniStat(value: '$appCount',                              label: 'Apps used'),
            _MiniStat(value: AppUsageModel.formatMinutes(avgMinutes), label: 'Daily avg'),
            _MiniStat(value: '$deltaPrefix$deltaAbs',                 label: 'vs avg',     valueColor: deltaColor),
            _MiniStat(
              value:      '$overLimitCount',
              label:      'Over limit',
              valueColor: overLimitCount > 0 ? AppTheme.danger : null,
            ),
          ]),
        ]),
      ),
    );
  }

  String _hhmm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;
  const _MiniStat({required this.value, required this.label, this.valueColor});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text(value,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
              color: valueColor ?? AppTheme.textPrimary)),
      const SizedBox(height: 2),
      Text(label,
          style: const TextStyle(fontSize: 10, color: AppTheme.textHint),
          textAlign: TextAlign.center),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────
//  Day progress pill
//  Replaces the arc CustomPainter clock. Shows the current hour
//  (e.g. "9AM") above a slim progress bar that mirrors the one
//  already in the hero card — consistent and readable at a glance.
// ─────────────────────────────────────────────────────────────

class _DayProgressPill extends StatelessWidget {
  final double progress;
  const _DayProgressPill({required this.progress});

  @override
  Widget build(BuildContext context) {
    final hour        = DateTime.now().hour;
    final period      = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$displayHour$period',
          style: const TextStyle(
            fontSize: 22,
            fontFamily: 'DMSerifDisplay',
            color: AppTheme.textPrimary,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: 50,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: AppTheme.surface2,
              valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Hero app card — stacked asymmetric layout
//
//  Flow:
//    1. Icon + name row
//    2. Giant time (dominant focal point — 52px)
//    3. % of day subtext
//    4. 3-up stat boxes
//    5. Progress bar (only when limit is set)
//
//  Border only appears in danger state — encodes meaning.
// ─────────────────────────────────────────────────────────────

class _HeroAppCard extends StatelessWidget {
  final AppUsageModel app;
  final int           totalMins;
  final VoidCallback  onTap;

  const _HeroAppCard({required this.app, required this.totalMins, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label     = app.appLabel.isNotEmpty ? app.appLabel : app.packageName;
    final overLimit = app.isOverLimit;
    final progress  = app.usageProgress;
    final pctOfDay  = totalMins > 0 ? (app.usageMinutes / (24 * 60) * 100).round() : 0;
    final timeColor = overLimit ? AppTheme.danger : AppTheme.textPrimary;
    final subColor  = overLimit ? AppTheme.danger : AppTheme.textHint;

    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: overLimit
              ? Border.all(color: AppTheme.danger.withValues(alpha: 0.35), width: 0.8)
              : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ① Icon + name row
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Stack(clipBehavior: Clip.none, children: [
              _AppIcon(packageName: app.packageName, rank: 0, size: 44),
              const Positioned(
                top: -8, left: -6,
                child: Text('👑', style: TextStyle(fontSize: 13)),
              ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  overLimit
                      ? 'Limit: ${app.formattedLimit} · Over by ${AppUsageModel.formatMinutes(-app.minutesRemaining!)}'
                      : app.limitMinutes != null
                          ? '${AppUsageModel.formatMinutes(app.minutesRemaining!)} remaining of ${app.formattedLimit}'
                          : 'Tap to set a daily limit',
                  style: TextStyle(fontSize: 11, color: subColor),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
          ]),

          // ② Giant time — the dominant focal point
          const SizedBox(height: 20),
          Text(
            app.formattedUsage,
            style: TextStyle(
              fontFamily: 'DMSerifDisplay', fontSize: 52,
              color: timeColor, height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$pctOfDay% of your day',
            style: TextStyle(
              fontSize: 12,
              color: (overLimit ? AppTheme.danger : AppTheme.accentLight).withValues(alpha: 0.50),
            ),
          ),

          // ③ 3-up stat boxes
          const SizedBox(height: 18),
          Row(children: [
            _HeroStatBox(
              value: overLimit && app.minutesRemaining != null
                  ? AppUsageModel.formatMinutes(-app.minutesRemaining!)
                  : '—',
              label: 'Over limit',
              danger: overLimit,
            ),
            const SizedBox(width: 8),
            _HeroStatBox(
              value: progress != null ? '${(progress * 100).round()}%' : '—',
              label: 'Limit used',
              danger: overLimit,
            ),
            const SizedBox(width: 8),
            const _HeroStatBox(value: '—', label: 'Sessions', danger: false),
          ]),

          // ④ Progress bar — only when limit is set
          if (progress != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0), minHeight: 4,
                backgroundColor: AppTheme.surface2,
                valueColor: AlwaysStoppedAnimation(
                    overLimit ? AppTheme.danger : AppTheme.teal),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _HeroStatBox extends StatelessWidget {
  final String value;
  final String label;
  final bool   danger;
  const _HeroStatBox({required this.value, required this.label, required this.danger});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(11)),
      child: Column(children: [
        Text(value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                color: danger ? AppTheme.danger : AppTheme.textPrimary)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppTheme.textHint),
            textAlign: TextAlign.center),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
//  Slat container
//  One shared rounded surface. Rows separated by hairlines.
//  This replaces N individual card outlines.
// ─────────────────────────────────────────────────────────────

class _SlatContainer extends StatelessWidget {
  final List<AppUsageModel>                  apps;
  final Future<void> Function(AppUsageModel) onSetLimit;

  const _SlatContainer({required this.apps, required this.onSetLimit});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: List.generate(apps.length, (i) => _AppUsageSlat(
        app:       apps[i],
        rank:      i + 2,
        isFirst:   i == 0,
        isLast:    i == apps.length - 1,
        onSetLimit: () => onSetLimit(apps[i]),
      )),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
//  App usage slat (rank 2+)
//
//  Design rules applied here:
//  • No individual card — lives inside _SlatContainer
//  • Separator replaces card outline
//  • Danger: left accent stripe + red text only (no tinted bg)
//  • Progress bar only when limit set AND progress > 10%
//  • Inline metric language preferred over redundant bars
// ─────────────────────────────────────────────────────────────

class _AppUsageSlat extends StatelessWidget {
  final AppUsageModel app;
  final int           rank;
  final bool          isFirst;
  final bool          isLast;
  final VoidCallback  onSetLimit;

  const _AppUsageSlat({
    required this.app,
    required this.rank,
    required this.isFirst,
    required this.isLast,
    required this.onSetLimit,
  });

  @override
  Widget build(BuildContext context) {
    final label     = app.appLabel.isNotEmpty ? app.appLabel : app.packageName;
    final overLimit = app.isOverLimit;
    final hasLimit  = app.limitMinutes != null;
    final progress  = app.usageProgress;

    final String subtitle;
    if (!hasLimit) {
      subtitle = 'Tap to set limit';
    } else if (overLimit) {
      subtitle = '${AppUsageModel.formatMinutes(-app.minutesRemaining!)} over · limit ${app.formattedLimit}';
    } else {
      subtitle = '${AppUsageModel.formatMinutes(app.minutesRemaining!)} left · limit ${app.formattedLimit}';
    }

    final subtitleColor = overLimit
        ? AppTheme.danger
        : hasLimit ? AppTheme.textSecond : AppTheme.textHint;

    final topRadius    = isFirst ? const Radius.circular(20) : Radius.zero;
    final bottomRadius = isLast  ? const Radius.circular(20) : Radius.zero;

    return Column(children: [
      if (!isFirst)
        const Divider(height: 1, indent: 68, color: Color(0x0963A8D2)),

      InkWell(
        onTap: () { HapticFeedback.lightImpact(); onSetLimit(); },
        borderRadius: BorderRadius.only(topLeft: topRadius, topRight: topRadius,
            bottomLeft: bottomRadius, bottomRight: bottomRadius),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

            if (overLimit)
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 166),
                  borderRadius: BorderRadius.only(topLeft: topRadius, bottomLeft: bottomRadius),
                ),
              ),

            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(overLimit ? 13 : 16, 13, 16, 13),
                child: Column(children: [
                  Row(children: [
                    SizedBox(
                      width: 16,
                      child: Text('$rank',
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                              color: AppTheme.textHint),
                          textAlign: TextAlign.center),
                    ),
                    const SizedBox(width: 10),
                    _AppIcon(packageName: app.packageName, rank: rank, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                                color: AppTheme.textPrimary),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: TextStyle(fontSize: 11, color: subtitleColor),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      app.formattedUsage,
                      style: TextStyle(
                        fontFamily: 'DMSerifDisplay', fontSize: 15, fontWeight: FontWeight.w600,
                        color: overLimit ? AppTheme.danger : AppTheme.textPrimary,
                      ),
                    ),
                  ]),

                  if (progress != null && progress > 0.1) ...[
                    const SizedBox(height: 9),
                    Padding(
                      padding: const EdgeInsets.only(left: 38),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0), minHeight: 2.5,
                          backgroundColor: AppTheme.surface2,
                          valueColor: AlwaysStoppedAnimation(
                              overLimit ? AppTheme.danger : AppTheme.teal),
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
//  App icon
// ─────────────────────────────────────────────────────────────

class _AppIcon extends StatefulWidget {
  final String packageName;
  final int    rank;
  final double size;
  const _AppIcon({required this.packageName, required this.rank, this.size = 40});

  @override
  State<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<_AppIcon> {
  Uint8List? _icon;
  bool       _loading = true;

  @override
  void initState() { super.initState(); _loadIcon(); }

  Future<void> _loadIcon() async {
    final bytes = await UsageChannel.getAppIcon(widget.packageName);
    if (mounted) setState(() { _icon = bytes; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    const fallbacks = [AppTheme.blue, AppTheme.teal, AppTheme.purple,
                       AppTheme.amber, AppTheme.rose, AppTheme.green];
    final color   = fallbacks[widget.rank % fallbacks.length];
    final initial = widget.packageName.isNotEmpty
        ? widget.packageName.split('.').last[0].toUpperCase() : '?';

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.size * 0.275),
      child: SizedBox(
        width: widget.size, height: widget.size,
        child: _loading
            ? Container(color: AppTheme.surface2)
            : _icon != null
                ? Image.memory(_icon!, fit: BoxFit.cover)
                : Container(
                    color: color.withValues(alpha: 38),
                    child: Center(
                      child: Text(initial,
                          style: TextStyle(fontSize: widget.size * 0.40,
                              fontWeight: FontWeight.w700, color: color)),
                    ),
                  ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Permission dialog
// ─────────────────────────────────────────────────────────────

class _PermissionDialog extends StatelessWidget {
  final VoidCallback onGrant;
  final VoidCallback onDismiss;
  const _PermissionDialog({required this.onGrant, required this.onDismiss});

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppTheme.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: const Text('Screen time access',
        style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
    content: const Text(
      'PhaseOut needs Usage Access to track how long you spend in each app '
      'and enforce your daily limits.\n\nOn the next screen, find PhaseOut and toggle it on.',
      style: TextStyle(color: AppTheme.textSecond, fontSize: 13, height: 1.6),
    ),
    actions: [
      TextButton(onPressed: onDismiss,
          child: const Text('Not now', style: TextStyle(color: AppTheme.textSecond))),
      TextButton(onPressed: onGrant,
          child: const Text('Grant access', style: TextStyle(color: AppTheme.accentLight))),
    ],
  );
}

// ─────────────────────────────────────────────────────────────
//  Limit bottom sheet
// ─────────────────────────────────────────────────────────────

class _LimitSheet extends StatefulWidget {
  final AppUsageModel app;
  const _LimitSheet({required this.app});

  @override
  State<_LimitSheet> createState() => _LimitSheetState();
}

class _LimitSheetState extends State<_LimitSheet> {
  late int _draft;

  @override
  void initState() {
    super.initState();
    _draft = (widget.app.limitMinutes ?? 60).clamp(15, 480);
  }

  @override
  Widget build(BuildContext context) {
    final label       = widget.app.appLabel.isNotEmpty
        ? widget.app.appLabel : widget.app.packageName;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36, height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(color: AppTheme.border2, borderRadius: BorderRadius.circular(2)),
        ),
        Row(children: [
          _AppIcon(packageName: widget.app.packageName, rank: 0),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const Text('Set daily time limit',
                  style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
            ]),
          ),
        ]),
        const SizedBox(height: 28),
        Text(AppUsageModel.formatMinutes(_draft),
            style: const TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 48,
                color: AppTheme.accentLight, height: 1)),
        const SizedBox(height: 4),
        Text('${_draft ~/ 60}h ${_draft % 60}m',
            style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
        const SizedBox(height: 16),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppTheme.accent, inactiveTrackColor: AppTheme.surface2,
            thumbColor: AppTheme.accentLight,
            overlayColor: AppTheme.accent.withOpacity(0.15), trackHeight: 4,
          ),
          child: Slider(
            value: _draft.toDouble(), min: 15, max: 480, divisions: 31,
            onChanged: (v) { HapticFeedback.selectionClick(); setState(() => _draft = v.round()); },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [30, 60, 90, 120].map((m) => _PresetChip(
            minutes: m, selected: _draft == m,
            onTap: () => setState(() => _draft = m),
          )).toList(),
        ),
        const SizedBox(height: 24),
        Row(children: [
          if (widget.app.limitMinutes != null) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, -1),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  side: BorderSide(color: AppTheme.danger.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Remove'),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _draft),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              child: const Text('Set limit'),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final int minutes; final bool selected; final VoidCallback onTap;
  const _PresetChip({required this.minutes, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.selectionClick(); onTap(); },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppTheme.accent.withOpacity(0.15) : AppTheme.surface2,
        borderRadius: BorderRadius.circular(8),
        border: selected ? Border.all(color: AppTheme.accent) : null,
      ),
      child: Text(AppUsageModel.formatMinutes(minutes),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: selected ? AppTheme.accentLight : AppTheme.textSecond)),
    ),
  );
}

// ── Helper ────────────────────────────────────────────────────
void unawaited(Future<void> future) { future.catchError((_) {}); }