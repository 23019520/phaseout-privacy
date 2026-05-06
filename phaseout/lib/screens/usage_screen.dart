// ─────────────────────────────────────────────────────────────
//  lib/screens/usage_screen.dart
//
//  FIX #3 — Usage access permission requested contextually
//  when this screen opens. Sync triggered on every open.
//
//  FIX #6 — Better app name sourcing:
//  - Uses getAppLabel() from MainActivity (real system label)
//  - Filters system/background packages (no launcher intent)
//  - Only shows apps with usage > 0 minutes AND a real name
//  - Excludes known system noise packages
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../channels/usage_channel.dart';
import '../db/database_helper.dart';
import '../models/app_usage_model.dart';
import '../services/usage_monitor_service.dart';

// System packages that should never appear in usage list
const _systemNoise = {
  'android', 'com.android.systemui', 'com.android.phone',
  'com.google.android.gms', 'com.google.android.gsf',
  'com.android.launcher', 'com.android.launcher3',
  'com.samsung.android.launcher', 'com.google.android.apps.nexuslauncher',
  'com.android.inputmethod', 'com.samsung.android.inputmethod',
  'com.android.providers', 'com.android.server',
  'com.android.keyguard', 'com.android.permissioncontroller',
};

class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key});
  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  List<AppUsageModel> _usage    = [];
  bool                _loading  = true;
  bool                _hasPerms = false;

  @override
  void initState() { super.initState(); _initScreen(); }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sync every time screen becomes active
    _initScreen();
  }

  Future<void> _initScreen() async {
    final hasPerms = await UsageChannel.hasUsagePermission();
    if (!hasPerms && mounted) {
      // #3 — Contextual permission request for usage screen
      await _requestUsagePermission();
      return;
    }
    setState(() => _hasPerms = true);
    // Sync on every open (#3 requirement)
    await UsageMonitorService.syncFromUI();
    await _loadFromDb();
  }

  Future<void> _requestUsagePermission() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Screen time access',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
        content: const Text(
          'PhaseOut needs Usage Access to track how long you spend in each app '
          'and enforce daily limits.\n\n'
          'On the next screen, find PhaseOut and toggle it on.',
          style: TextStyle(color: AppTheme.textSecond,
              fontSize: 13, height: 1.55)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Not now',
                  style: TextStyle(color: AppTheme.textSecond))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await UsageChannel.openUsageSettings();
              // Re-check on return
              await Future.delayed(const Duration(seconds: 1));
              if (mounted) _initScreen();
            },
            child: const Text('Grant access',
                style: TextStyle(color: AppTheme.accentLight)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadFromDb() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final raw = await DatabaseHelper.instance
        .getUsageForDate(AppUsageModel.todayString());

    // FIX #6: filter and enrich app names
    final cleaned = <AppUsageModel>[];
    for (final app in raw) {
      // Skip system noise
      if (_systemNoise.contains(app.packageName)) continue;
      if (app.packageName.startsWith('com.android.server')) continue;
      if (app.packageName.startsWith('com.google.android.gms')) continue;
      // Skip zero-usage entries
      if (app.usageMinutes <= 0) continue;

      // Get real label from system if stored label is empty or is package name
      String label = app.appLabel;
      if (label.isEmpty || label == app.packageName || label.contains('.')) {
        label = await UsageChannel.getAppLabel(app.packageName);
      }

      cleaned.add(AppUsageModel(
        packageName:  app.packageName,
        appLabel:     label,
        date:         app.date,
        usageMinutes: app.usageMinutes,
        limitMinutes: app.limitMinutes,
      ));
    }

    // Sort by usage descending
    cleaned.sort((a, b) => b.usageMinutes.compareTo(a.usageMinutes));

    if (mounted) setState(() { _usage = cleaned; _loading = false; });
  }

  Future<void> _setLimit(AppUsageModel app) async {
    int? result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        int minutes = app.limitMinutes ?? 60;
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text('Daily limit — ${app.appLabel}',
              style: const TextStyle(color: AppTheme.textPrimary,
                  fontSize: 14)),
          content: StatefulBuilder(
            builder: (_, setInner) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$minutes minutes',
                    style: const TextStyle(fontFamily: 'DMSerifDisplay',
                        fontSize: 32, color: AppTheme.accentLight)),
                Slider(
                  value:    minutes.toDouble(),
                  min:      15, max: 480, divisions: 31,
                  activeColor: AppTheme.accent,
                  onChanged: (v) =>
                      setInner(() => minutes = v.round()),
                ),
                Text('${minutes ~/ 60}h ${minutes % 60}m',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecond)),
              ],
            ),
          ),
          actions: [
            if (app.limitMinutes != null)
              TextButton(onPressed: () => Navigator.pop(ctx, -1),
                  child: const Text('Remove limit',
                      style: TextStyle(color: AppTheme.danger))),
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: AppTheme.textSecond))),
            TextButton(onPressed: () => Navigator.pop(ctx, minutes),
                child: const Text('Set',
                    style: TextStyle(color: AppTheme.accentLight))),
          ],
        );
      },
    );

    if (result == null) return;
    if (result == -1) {
      await UsageMonitorService.setLimit(app.packageName, 0);
    } else {
      await UsageMonitorService.setLimit(app.packageName, result);
    }
    await _loadFromDb();
  }

  String _totalLabel() {
    final total = _usage.fold(0, (s, a) => s + a.usageMinutes);
    if (total < 60) return '${total}m';
    return '${total ~/ 60}h ${total % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPerms) {
      return Scaffold(
        backgroundColor: AppTheme.navy,
        appBar: AppBar(title: const Text('Usage')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.bar_chart_rounded,
                size: 48, color: AppTheme.textHint),
            const SizedBox(height: 16),
            const Text('Usage access needed',
                style: TextStyle(fontSize: 16,
                    fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            const Text('Grant permission to see screen time',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecond)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _initScreen,
              child: const Text('Grant access'),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        title: const Text('Usage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded, size: 20),
            onPressed: () async {
              await UsageMonitorService.syncFromUI();
              await _loadFromDb();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _usage.isEmpty
              ? const Center(
                  child: Text('No usage data for today.',
                      style: TextStyle(color: AppTheme.textSecond)))
              : RefreshIndicator(
                  onRefresh: () async {
                    await UsageMonitorService.syncFromUI();
                    await _loadFromDb();
                  },
                  color: AppTheme.accent,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [

                      // Total today
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(children: [
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Total screen time today',
                                  style: TextStyle(fontSize: 12,
                                      color: AppTheme.textSecond)),
                              const SizedBox(height: 4),
                              Text(_totalLabel(),
                                  style: const TextStyle(
                                      fontFamily: 'DMSerifDisplay',
                                      fontSize: 28,
                                      color: AppTheme.textPrimary)),
                            ],
                          )),
                          const Icon(Icons.phone_android_rounded,
                              color: AppTheme.textHint, size: 28),
                        ]),
                      ),

                      const SizedBox(height: 20),

                      // App list
                      const Text('APPS TODAY',
                          style: TextStyle(fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textHint, letterSpacing: 1.2)),
                      const SizedBox(height: 10),

                      ..._usage.map((app) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _AppUsageTile(
                          app:      app,
                          onSetLimit: () => _setLimit(app),
                        ),
                      )),
                    ],
                  ),
                ),
    );
  }
}

class _AppUsageTile extends StatelessWidget {
  final AppUsageModel app;
  final VoidCallback  onSetLimit;
  const _AppUsageTile({required this.app, required this.onSetLimit});

  String _fmt(int m) =>
      m < 60 ? '${m}m' : '${m ~/ 60}h ${m % 60}m';

  @override
  Widget build(BuildContext context) {
    final overLimit = app.isOverLimit;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: overLimit
              ? AppTheme.danger.withValues(alpha: 0.3) : AppTheme.border,
        ),
      ),
      child: Column(children: [
        Row(children: [
          Container(width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              borderRadius: BorderRadius.circular(9)),
            child: Center(child: Text(
              app.appLabel.isNotEmpty
                  ? app.appLabel[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentLight)))),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(app.appLabel.isNotEmpty
                    ? app.appLabel : app.packageName,
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary)),
            if (app.limitMinutes != null)
              Text('Limit: ${_fmt(app.limitMinutes!)}',
                  style: TextStyle(fontSize: 10,
                      color: overLimit
                          ? AppTheme.danger : AppTheme.textHint)),
          ])),
          Text(_fmt(app.usageMinutes),
              style: TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: overLimit
                      ? AppTheme.danger : AppTheme.textPrimary)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSetLimit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppTheme.accentLight.withValues(alpha: 0.2)),
              ),
              child: const Text('Limit',
                  style: TextStyle(fontSize: 10,
                      color: AppTheme.accentLight,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
        if (app.limitMinutes != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (app.usageMinutes / app.limitMinutes!).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AppTheme.surface2,
              valueColor: AlwaysStoppedAnimation<Color>(
                  overLimit ? AppTheme.danger : AppTheme.accent),
            ),
          ),
        ],
      ]),
    );
  }
}