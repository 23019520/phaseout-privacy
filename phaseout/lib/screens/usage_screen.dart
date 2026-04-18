// ─────────────────────────────────────────────────────────────
//  lib/screens/usage_screen.dart
//  Shows per-screen intro with PACKAGE_USAGE_STATS permission
//  on first open. No skip option.
// ─────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../channels/usage_channel.dart';
import '../db/database_helper.dart';
import '../models/app_usage_model.dart';
import '../services/app_label_service.dart';
import '../services/battery_prediction_service.dart';
import '../services/usage_monitor_service.dart';
import '../widgets/screen_intro_overlay.dart';

class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key});
  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen>
    with SingleTickerProviderStateMixin {

  List<AppUsageModel> _usage         = [];
  bool                _loading       = true;
  bool                _syncing       = false;
  String?             _prediction;
  String?             _dischargeRate;
  int?                _phoneLimitMin;
  List<int>           _dayTotals     = List.filled(7, 0);

  late final AnimationController _barCtrl;
  late final Animation<double>   _barAnim;

  @override
  void initState() {
    super.initState();
    _barCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _barAnim =
        CurvedAnimation(parent: _barCtrl, curve: Curves.easeOutCubic);
    _load();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _showIntroIfNeeded());
  }

  @override
  void dispose() {
    _barCtrl.dispose();
    super.dispose();
  }

  Future<void> _showIntroIfNeeded() async {
    await ScreenIntroOverlay.showIfNeeded(
      context,
      screenKey: 'usage_screen',
      title:     'Usage & Analytics',
      subtitle:
          'Understand your screen habits, set limits, and see battery predictions.',
      features: const [
        ScreenFeature(
          icon:     Icons.bar_chart_rounded,
          color:    AppTheme.tealLight,
          title:    'Per-app screen time',
          subtitle: 'See exactly how long you spend in each app today',
        ),
        ScreenFeature(
          icon:     Icons.calendar_view_week_rounded,
          color:    Color(0xFF60A5FA),
          title:    'Busiest day analysis',
          subtitle: 'Which day of the week do you use your phone most?',
        ),
        ScreenFeature(
          icon:     Icons.battery_charging_full_rounded,
          color:    Color(0xFF34D399),
          title:    'Battery prediction',
          subtitle: 'ML model predicts when your battery hits 20%',
        ),
        ScreenFeature(
          icon:     Icons.timer_off_rounded,
          color:    AppTheme.warning,
          title:    'App limits',
          subtitle: 'Set daily limits — get an overlay when you hit them',
        ),
      ],
      permission: ScreenPermission(
        icon:  Icons.bar_chart_rounded,
        color: AppTheme.tealLight,
        title: 'Usage Access',
        reason:
            'PhaseOut needs access to Android\'s usage stats to show your per-app screen time. This data stays on your device — it is never uploaded.',
        onGrant: () async => UsageChannel.openUsageSettings(),
        checkGranted: () => UsageChannel.hasUsagePermission(),
      ),
    );
    // Re-load after permission may have been granted
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    await AppLabelService.refreshTodayLabels();
    final data = await DatabaseHelper.instance
        .getUsageForDate(AppUsageModel.todayString());
    data.sort((a, b) => b.usageMinutes.compareTo(a.usageMinutes));
    final pred     = await BatteryPredictionService.predictLowBatteryTime();
    final rate     = await BatteryPredictionService.averageDischargeRate();
    final dayTots  = await _calcDayTotals();
    if (!mounted) return;
    setState(() {
      _usage         = data;
      _prediction    = pred;
      _dischargeRate = rate;
      _dayTotals     = dayTots;
      _loading       = false;
    });
    _barCtrl.forward(from: 0);
    final over = data.where((a) => a.isOverLimit).toList();
    if (over.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) _showOverLimitSheet(over.first);
    }
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    await UsageMonitorService.syncFromUI();
    await _load();
    if (mounted) setState(() => _syncing = false);
  }

  Future<List<int>> _calcDayTotals() async {
    final totals = List.filled(7, 0);
    final now    = DateTime.now();
    for (var d = 0; d < 7; d++) {
      final date    = now.subtract(Duration(days: 6 - d));
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
      final rows    = await DatabaseHelper.instance.getUsageForDate(dateStr);
      totals[d]     = rows.fold(0, (s, a) => s + a.usageMinutes);
    }
    return totals;
  }

  int get _totalMin => _usage.fold(0, (s, a) => s + a.usageMinutes);

  String _fmt(int m) {
    if (m == 0) return '0m';
    if (m < 60) return '${m}m';
    final h   = m ~/ 60;
    final min = m % 60;
    return min == 0 ? '${h}h' : '${h}h ${min}m';
  }

  Future<void> _setLimit(AppUsageModel app) async {
    final result = await _showLimitSheet(
      label:        app.appLabel.isNotEmpty ? app.appLabel : app.packageName,
      initialLimit: app.limitMinutes ?? 60,
    );
    if (result != null) {
      await UsageMonitorService.setLimit(app.packageName, result);
      _load();
    }
  }

  Future<void> _setPhoneLimit() async {
    final result = await _showLimitSheet(
      label:        'Total phone usage',
      initialLimit: _phoneLimitMin ?? 120,
      isPhone:      true,
    );
    if (result != null && mounted) setState(() => _phoneLimitMin = result);
  }

  Future<int?> _showLimitSheet(
      {required String label,
      required int initialLimit,
      bool isPhone = false}) {
    return showModalBottomSheet<int>(
      context:             context,
      backgroundColor:     AppTheme.surface,
      isScrollControlled:  true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _LimitSheet(
          label: label, initialLimit: initialLimit, isPhone: isPhone),
    );
  }

  void _showOverLimitSheet(AppUsageModel app) {
    showModalBottomSheet(
      context:             context,
      backgroundColor:     Colors.transparent,
      isScrollControlled:  true,
      builder: (_) => _OverLimitSheet(app: app),
    );
  }

  bool get _overPhone =>
      _phoneLimitMin != null && _totalMin >= _phoneLimitMin!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        title: const Text('Usage'),
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.accentLight)),
            )
          else
            TextButton(
              onPressed: _sync,
              child: const Text('Sync',
                style: TextStyle(
                    color: AppTheme.accentLight, fontSize: 13)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.accent,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [

                  // ── Today hero ───────────────────────────
                  _TodayCard(
                    total:         _totalMin,
                    phoneLimitMin: _phoneLimitMin,
                    overPhone:     _overPhone,
                    fmt:           _fmt,
                    onSetLimit:    _setPhoneLimit,
                  ),
                  const SizedBox(height: 28),

                  // ── Busiest days ─────────────────────────
                  if (_dayTotals.any((d) => d > 0)) ...[
                    const _SectionHeader('Busiest days', 'Last 7 days'),
                    const SizedBox(height: 12),
                    _BusiestDaysChart(
                        dayTotals: _dayTotals, fmt: _fmt),
                    const SizedBox(height: 28),
                  ],

                  // ── Battery ──────────────────────────────
                  if (_prediction != null || _dischargeRate != null) ...[
                    const _SectionHeader(
                        'Battery intelligence', 'ML · updated daily'),
                    const SizedBox(height: 12),
                    _BatteryCard(
                        prediction:    _prediction,
                        dischargeRate: _dischargeRate),
                    const SizedBox(height: 28),
                  ],

                  // ── Apps ─────────────────────────────────
                  if (_usage.isNotEmpty) ...[
                    const _SectionHeader(
                        "Today's apps", 'Tap to set a limit'),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      decoration: BoxDecoration(
                          color:        AppTheme.surface2,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border)),
                      child: AnimatedBuilder(
                        animation: _barAnim,
                        builder: (_, __) => _AppBarChart(
                          usage:    _usage.take(7).toList(),
                          progress: _barAnim.value,
                          onTap:    _setLimit,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ..._usage.map((a) =>
                        _AppListRow(app: a, onTap: () => _setLimit(a))),
                  ],

                  if (_usage.isEmpty) const _EmptyState(),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  SUB-WIDGETS (same as before but kept local)
// ─────────────────────────────────────────────────────────────

class _TodayCard extends StatelessWidget {
  final int    total;
  final int?   phoneLimitMin;
  final bool   overPhone;
  final String Function(int) fmt;
  final VoidCallback onSetLimit;
  const _TodayCard({required this.total, required this.phoneLimitMin,
      required this.overPhone, required this.fmt, required this.onSetLimit});

  @override
  Widget build(BuildContext context) {
    final frac = phoneLimitMin != null
        ? (total / phoneLimitMin!).clamp(0.0, 1.0) : 0.0;
    final barColor = frac >= 1.0 ? AppTheme.danger
        : frac >= 0.8 ? AppTheme.warning : AppTheme.accent;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1A2D50), Color(0xFF0D1A30)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: overPhone
            ? AppTheme.danger.withValues(alpha: 0.45)
            : Colors.white.withValues(alpha: 0.08))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Today's screen time", style: TextStyle(
                fontSize: 11, color: AppTheme.textSecond, letterSpacing: 0.4)),
            const SizedBox(height: 6),
            Text(fmt(total), style: TextStyle(fontFamily: 'DMSerifDisplay',
                fontSize: 38, color: overPhone ? AppTheme.danger : Colors.white, height: 1)),
          ])),
          GestureDetector(onTap: onSetLimit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: overPhone ? AppTheme.danger.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: overPhone
                    ? AppTheme.danger.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.1))),
              child: Column(children: [
                Icon(phoneLimitMin != null ? Icons.phone_android_rounded : Icons.add_rounded,
                    size: 18, color: overPhone ? AppTheme.danger : AppTheme.accentLight),
                const SizedBox(height: 4),
                Text(phoneLimitMin != null ? fmt(phoneLimitMin!) : 'Set\nlimit',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                        color: overPhone ? AppTheme.danger : AppTheme.accentLight, height: 1.3)),
              ]),
            )),
        ]),
        if (phoneLimitMin != null) ...[
          const SizedBox(height: 16),
          ClipRRect(borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac, minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              valueColor: AlwaysStoppedAnimation(barColor))),
          const SizedBox(height: 8),
          Text(overPhone ? 'Daily phone limit reached'
              : '${fmt(total)} of ${fmt(phoneLimitMin!)} limit',
              style: TextStyle(fontSize: 11,
                  color: overPhone ? AppTheme.danger : AppTheme.textSecond)),
        ],
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title, sub;
  const _SectionHeader(this.title, this.sub);
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(title, style: const TextStyle(fontSize: 13,
          fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      const SizedBox(width: 8),
      Text(sub, style: const TextStyle(fontSize: 10, color: AppTheme.textHint)),
    ]);
}

class _BusiestDaysChart extends StatelessWidget {
  final List<int> dayTotals;
  final String Function(int) fmt;
  const _BusiestDaysChart({required this.dayTotals, required this.fmt});
  static const _labels = ['M','T','W','T','F','S','S'];
  static const _names  = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
  @override
  Widget build(BuildContext context) {
    final maxVal  = dayTotals.reduce(math.max).clamp(1, 999999);
    final busiest = dayTotals.indexOf(dayTotals.reduce(math.max));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border)),
      child: Column(children: [
        SizedBox(height: 72,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) {
              final frac = dayTotals[i] / maxVal;
              final isBusiest = i == busiest && dayTotals[i] > 0;
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 550),
                    curve: Curves.easeOutCubic,
                    height: (frac * 60).clamp(3.0, 60.0),
                    decoration: BoxDecoration(
                      color: isBusiest ? AppTheme.warning
                          : AppTheme.accent.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(5)),
                  ),
                ])));
            }))),
        const SizedBox(height: 8),
        Row(children: List.generate(7, (i) {
          final isBusiest = i == busiest && dayTotals[i] > 0;
          return Expanded(child: Text(_labels[i],
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11,
                fontWeight: isBusiest ? FontWeight.w700 : FontWeight.w400,
                color: isBusiest ? AppTheme.warning : AppTheme.textHint)));
        })),
        if (dayTotals[busiest] > 0) ...[
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.insights_rounded, size: 13, color: AppTheme.warning),
            const SizedBox(width: 6),
            Text('${_names[busiest]} is your heaviest screen day',
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecond)),
          ]),
        ],
      ]),
    );
  }
}

class _BatteryCard extends StatelessWidget {
  final String? prediction, dischargeRate;
  const _BatteryCard({this.prediction, this.dischargeRate});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 40, height: 40,
          decoration: BoxDecoration(color: AppTheme.tealLight.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.battery_charging_full_rounded,
              color: AppTheme.tealLight, size: 20)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Low battery predicted at',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecond)),
          const SizedBox(height: 2),
          Text(prediction ?? 'Gathering data…',
              style: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 22,
                  color: prediction != null ? AppTheme.tealLight : AppTheme.textHint, height: 1.1)),
        ])),
      ]),
      if (dischargeRate != null) ...[
        const SizedBox(height: 14),
        const Divider(color: Colors.white10, height: 1),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.trending_down_rounded, size: 13, color: AppTheme.textHint),
          const SizedBox(width: 6),
          Expanded(child: Text('Discharge rate: $dischargeRate · recalculated daily from 28-day history',
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecond, height: 1.4))),
        ]),
      ],
    ]),
  );
}

class _AppBarChart extends StatelessWidget {
  final List<AppUsageModel> usage;
  final double progress;
  final ValueChanged<AppUsageModel> onTap;
  const _AppBarChart({required this.usage, required this.progress, required this.onTap});
  static const _palette = [
    Color(0xFF60A5FA), Color(0xFF34D399), Color(0xFFA78BFA),
    Color(0xFFFBBF24), Color(0xFFF472B6), Color(0xFF38BDF8), Color(0xFF4ADE80),
  ];
  @override
  Widget build(BuildContext context) {
    if (usage.isEmpty) return const SizedBox.shrink();
    final maxMin = usage.first.usageMinutes.toDouble().clamp(1.0, 9999.0);
    return Column(children: usage.asMap().entries.map((e) {
      final i     = e.key; final app = e.value;
      final frac  = (app.usageMinutes / maxMin).clamp(0.0, 1.0);
      final color = app.isOverLimit ? AppTheme.danger : _palette[i % _palette.length];
      final label = app.appLabel.isNotEmpty ? app.appLabel : app.packageName.split('.').last;
      return GestureDetector(onTap: () => onTap(app),
        child: Padding(padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            SizedBox(width: 68, child: Text(label, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecond))),
            const SizedBox(width: 8),
            Expanded(child: LayoutBuilder(builder: (_, c) {
              final barW = c.maxWidth * frac * progress;
              return Stack(children: [
                Container(height: 22, width: c.maxWidth,
                    decoration: BoxDecoration(color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(5))),
                Container(height: 22, width: math.max(barW, 4),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(5))),
              ]);
            })),
            const SizedBox(width: 8),
            SizedBox(width: 36, child: Text(app.formattedUsage, textAlign: TextAlign.right,
                style: TextStyle(fontSize: 10,
                    color: app.isOverLimit ? AppTheme.danger : AppTheme.textSecond,
                    fontWeight: app.isOverLimit ? FontWeight.w600 : FontWeight.w400))),
          ])));
    }).toList());
  }
}

class _AppListRow extends StatelessWidget {
  final AppUsageModel app; final VoidCallback onTap;
  const _AppListRow({required this.app, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final label   = app.appLabel.isNotEmpty ? app.appLabel : app.packageName.split('.').last;
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Container(width: 34, height: 34,
            decoration: BoxDecoration(color: AppTheme.surface2, borderRadius: BorderRadius.circular(9)),
            child: Center(child: Text(initial, style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.accentLight)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
            if (app.limitMinutes != null)
              Text('Limit: ${app.formattedLimit}',
                  style: const TextStyle(fontSize: 10, color: AppTheme.textHint)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(app.formattedUsage, style: TextStyle(fontSize: 12,
                color: app.isOverLimit ? AppTheme.danger : AppTheme.textSecond,
                fontWeight: app.isOverLimit ? FontWeight.w600 : FontWeight.w400)),
            if (app.isOverLimit) const Text('Over limit',
                style: TextStyle(fontSize: 9, color: AppTheme.danger, fontWeight: FontWeight.w500)),
          ]),
        ])));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(padding: EdgeInsets.symmetric(vertical: 60),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.bar_chart_rounded, size: 48, color: AppTheme.textHint),
        SizedBox(height: 14),
        Text('No usage data yet', style: TextStyle(fontSize: 15, color: AppTheme.textSecond)),
        SizedBox(height: 8),
        Text('Grant usage access then tap Sync.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textHint, height: 1.5)),
      ])));
}

class _OverLimitSheet extends StatelessWidget {
  final AppUsageModel app;
  const _OverLimitSheet({required this.app});
  @override
  Widget build(BuildContext context) {
    final label = app.appLabel.isNotEmpty ? app.appLabel : app.packageName;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(color: const Color(0xFF0D1A30),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3))),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppTheme.textHint,
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 22),
        Container(width: 52, height: 52,
          decoration: BoxDecoration(color: AppTheme.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3))),
          child: const Icon(Icons.timer_off_rounded, color: AppTheme.danger, size: 24)),
        const SizedBox(height: 16),
        Text('$label limit reached', textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 20, color: Colors.white)),
        const SizedBox(height: 8),
        Text("You've used ${app.formattedUsage} of ${app.formattedLimit} today.",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppTheme.textSecond, height: 1.5)),
        const SizedBox(height: 4),
        const Text("You set this limit. You're still in control.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textHint, fontStyle: FontStyle.italic, height: 1.5)),
        const SizedBox(height: 22),
        SizedBox(width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              backgroundColor: AppTheme.danger.withValues(alpha: 0.1),
              foregroundColor: AppTheme.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.35))),
              padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Got it', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)))),
      ]),
    );
  }
}

class _LimitSheet extends StatefulWidget {
  final String label; final int initialLimit; final bool isPhone;
  const _LimitSheet({required this.label, required this.initialLimit, this.isPhone = false});
  @override State<_LimitSheet> createState() => _LimitSheetState();
}

class _LimitSheetState extends State<_LimitSheet> {
  late int _minutes;
  @override void initState() { super.initState(); _minutes = widget.initialLimit; }
  String get _label {
    if (_minutes < 60) return '$_minutes min';
    final h = _minutes ~/ 60; final m = _minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Container(padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppTheme.textHint, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Align(alignment: Alignment.centerLeft,
          child: Text(widget.isPhone ? 'Daily phone limit' : widget.label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary))),
        const SizedBox(height: 20),
        Text(_label, style: const TextStyle(fontFamily: 'DMSerifDisplay',
            fontSize: 40, color: AppTheme.accentLight, height: 1)),
        const SizedBox(height: 16),
        Slider(value: _minutes.toDouble(), min: 5, max: 480, divisions: 95,
            activeColor: AppTheme.accent, inactiveColor: AppTheme.surface2,
            onChanged: (v) => setState(() => _minutes = v.round())),
        const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('5 min', style: TextStyle(fontSize: 10, color: AppTheme.textHint)),
              Text('8 h', style: TextStyle(fontSize: 10, color: AppTheme.textHint)),
            ]),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.textSecond,
                side: const BorderSide(color: AppTheme.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Cancel'))),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(
            onPressed: () => Navigator.pop(context, _minutes),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Set limit', style: TextStyle(fontWeight: FontWeight.w600)))),
        ]),
      ])));
}