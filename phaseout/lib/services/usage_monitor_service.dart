// ─────────────────────────────────────────────────────────────
//  lib/services/usage_monitor_service.dart
//  PhaseOut — Usage monitoring (Flutter UI sync layer)
//
//  PhaseOutService handles limit enforcement + notifications.
//  This service syncs usage data to DB for display in the
//  usage screen. Runs on the main isolate — direct channel
//  calls are safe here.
// ─────────────────────────────────────────────────────────────

import '../channels/usage_channel.dart';
import '../db/database_helper.dart';
import '../models/app_usage_model.dart';
import '../services/notification_service.dart';
import '../utils/logger.dart';

class UsageMonitorService {

  static const String _tag = 'UsageMonitorService';
  UsageMonitorService._();

  static final Set<String> _notifiedToday = {};
  static String _lastResetDate = AppUsageModel.todayString();

  // ── Sync from OS → DB ────────────────────────────────────
  // Safe to call from Flutter BGS tick or UI.
  static Future<void> checkLimits() async {
    AppLogger.bg(_tag, 'Syncing usage data');
    _resetIfNewDay();

    bool granted = false;
    try {
      granted = await UsageChannel.hasUsagePermission();
    } catch (e) {
      AppLogger.bg(_tag, 'Usage permission check failed: $e');
      await _evaluateLimits();
      return;
    }

    if (!granted) {
      AppLogger.bg(_tag, 'Usage permission not granted');
      return;
    }

    await _fetchAndStore();
    await _evaluateLimits();
  }

  // ── UI-facing sync (called from Sync button) ──────────────
  static Future<void> syncFromUI() async {
    try {
      final granted = await UsageChannel.hasUsagePermission();
      if (!granted) return;
      final stats = await UsageChannel.getTodayStats();
      if (stats.isNotEmpty) await _storeStats(stats);
      await _evaluateLimits();
    } catch (e) {
      AppLogger.i(_tag, 'syncFromUI failed: $e');
    }
  }

  static Future<void> _fetchAndStore() async {
    Map<String, int> stats;
    try {
      stats = await UsageChannel.getTodayStats();
    } catch (e) {
      AppLogger.bg(_tag, 'getTodayStats failed: $e');
      return;
    }
    if (stats.isEmpty) return;
    await _storeStats(stats);
  }

  static Future<void> _storeStats(Map<String, int> stats) async {
    AppLogger.bg(_tag, 'Writing usage for ${stats.length} apps to DB');
    final today = AppUsageModel.todayString();
    for (final entry in stats.entries) {
      try {
        final existing = await DatabaseHelper.instance
            .getUsageForPackage(entry.key, today);
        final model = AppUsageModel(
          packageName:  entry.key,
          appLabel:     existing?.appLabel ?? entry.key,
          date:         today,
          usageMinutes: entry.value,
          limitMinutes: existing?.limitMinutes,
        );
        await DatabaseHelper.instance.insertOrUpdateUsage(model);
      } catch (e) {
        AppLogger.bg(_tag, 'Failed to store ${entry.key}: $e');
      }
    }
  }

  static Future<void> _evaluateLimits() async {
    final overLimit = await DatabaseHelper.instance.getAppsOverLimit();
    if (overLimit.isEmpty) {
      AppLogger.bg(_tag, 'No apps over limit');
      return;
    }
    for (final app in overLimit) {
      if (_notifiedToday.contains(app.packageName)) continue;
      AppLogger.bg(_tag,
          '${app.packageName} over limit: '
          '${app.formattedUsage} / ${app.formattedLimit}');
      final label = app.appLabel == app.packageName ? 'an app' : app.appLabel;
      await NotificationService.sendScheduledReminder(
        'Daily limit reached',
        'You have used $label for ${app.formattedUsage} today '
        '(limit: ${app.formattedLimit}).',
      );
      _notifiedToday.add(app.packageName);
    }
  }

  static void _resetIfNewDay() {
    final today = AppUsageModel.todayString();
    if (today != _lastResetDate) {
      _notifiedToday.clear();
      _lastResetDate = today;
    }
  }

  static Future<void> setLimit(String packageName, int limitMinutes) async {
    await DatabaseHelper.instance.setAppLimit(packageName, limitMinutes);
    AppLogger.i(_tag, 'Limit set: $packageName = ${limitMinutes}m/day');
  }

  static Future<List<AppUsageModel>> getTodayUsage() async {
    return DatabaseHelper.instance.getUsageForDate(
        AppUsageModel.todayString());
  }
}