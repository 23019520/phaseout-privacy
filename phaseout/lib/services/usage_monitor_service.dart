// ─────────────────────────────────────────────────────────────
//  lib/services/usage_monitor_service.dart
//  PhaseOut — App usage monitoring and limit enforcement
//
//  Called every 60 seconds by the BGS tick loop.
//  Reads today's usage from UsageStatsManager, writes to DB,
//  and fires a notification when a limit is exceeded.
//
//  Runs inside the background isolate — use AppLogger.bg().
// ─────────────────────────────────────────────────────────────

import '../channels/usage_channel.dart';
import '../db/database_helper.dart';
import '../models/app_usage_model.dart';
import '../services/notification_service.dart';
//import '../utils/constants.dart';
import '../utils/logger.dart';

class UsageMonitorService {

  static const String _tag = 'UsageMonitorService';

  UsageMonitorService._();

  // Tracks which packages have already been notified today.
  // Resets at midnight via _resetIfNewDay().
  static final Set<String> _notifiedToday = {};
  static String _lastResetDate = AppUsageModel.todayString();

  // ── Main entry point ──────────────────────────────────────
  // Called by SchedulerService on every BGS tick.
  static Future<void> checkLimits() async {
    AppLogger.bg(_tag, 'Checking usage limits');

    _resetIfNewDay();

    final granted = await UsageChannel.hasUsagePermission();
    if (!granted) {
      AppLogger.bg(_tag, 'PACKAGE_USAGE_STATS not granted — skipping');
      return;
    }

    await _fetchAndStore();
    await _evaluateLimits();
  }

  // ── Fetch from OS and write to DB ─────────────────────────
  static Future<void> _fetchAndStore() async {
    final stats = await UsageChannel.getTodayStats();

    if (stats.isEmpty) {
      AppLogger.bg(_tag, 'No usage stats returned from OS');
      return;
    }

    AppLogger.bg(_tag, 'Writing usage for ${stats.length} apps to DB');

    final today = AppUsageModel.todayString();

    for (final entry in stats.entries) {
      try {
        // Get existing row to preserve any limit the user set
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
        AppLogger.bg(_tag, 'Failed to store usage for ${entry.key}: $e');
      }
    }
  }

  // ── Check limits and notify ────────────────────────────────
  static Future<void> _evaluateLimits() async {
    final overLimit = await DatabaseHelper.instance.getAppsOverLimit();

    if (overLimit.isEmpty) {
      AppLogger.bg(_tag, 'No apps over limit');
      return;
    }

    for (final app in overLimit) {
      if (_alreadyNotifiedToday(app.packageName)) {
        AppLogger.bg(_tag, '${app.packageName} already notified today');
        continue;
      }

      AppLogger.bg(_tag,
        '${app.packageName} over limit: ${app.formattedUsage} / ${app.formattedLimit}');

      await _notifyUser(app);
      _notifiedToday.add(app.packageName);
    }
  }

  // ── Send usage limit notification ─────────────────────────
  static Future<void> _notifyUser(AppUsageModel app) async {
    final label = app.appLabel == app.packageName
        ? 'an app'
        : app.appLabel;

    await NotificationService.sendScheduledReminder(
      'Daily limit reached',
      'You have used $label for ${app.formattedUsage} today '
      '(limit: ${app.formattedLimit}).',
    );

    AppLogger.bg(_tag, 'Notified: ${app.packageName}');
  }

  // ── Already notified guard ────────────────────────────────
  static bool _alreadyNotifiedToday(String packageName) {
    return _notifiedToday.contains(packageName);
  }

  // ── Reset at midnight ─────────────────────────────────────
  static void _resetIfNewDay() {
    final today = AppUsageModel.todayString();
    if (today != _lastResetDate) {
      AppLogger.bg(_tag, 'New day — resetting notification tracker');
      _notifiedToday.clear();
      _lastResetDate = today;
    }
  }

  // ── Set a limit (called from UI) ──────────────────────────
  static Future<void> setLimit(
    String packageName,
    int limitMinutes,
  ) async {
    await DatabaseHelper.instance.setAppLimit(packageName, limitMinutes);
    AppLogger.i(_tag, 'Limit set: $packageName = ${limitMinutes}m/day');
  }

  // ── Get today's full usage list (called from UI) ──────────
  static Future<List<AppUsageModel>> getTodayUsage() async {
    return DatabaseHelper.instance.getUsageForDate(
      AppUsageModel.todayString(),
    );
  }
}