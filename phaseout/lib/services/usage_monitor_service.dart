// ─────────────────────────────────────────────────────────────
//  lib/services/usage_monitor_service.dart
//
//  FIXES:
//  - upsertAppUsage() → insertOrUpdateUsage()     (correct DB method name)
//  - AppUsageModel now passes appLabel: ''          (required named param)
//  - _checkLimits() is private — not exposed publicly
//  - getTodayStats() → getStatsForRange(startMs, endMs)
//  - scheduler_service.dart calls syncFromBgs() not checkLimits()
// ─────────────────────────────────────────────────────────────

import '../channels/usage_channel.dart';
import '../db/database_helper.dart';
import '../models/app_usage_model.dart';
import '../services/notification_service.dart';
import '../utils/logger.dart';

class UsageMonitorService {

  static const String _tag = 'UsageMonitorService';

  UsageMonitorService._();

  // ── Sync usage from system into local DB (UI / main isolate) ─
  static Future<void> syncFromUI() async {
    try {
      final now        = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day)
          .millisecondsSinceEpoch;
      final endMs      = now.millisecondsSinceEpoch;

      final stats = await UsageChannel.getStatsForRange(startOfDay, endMs);
      if (stats.isEmpty) {
        AppLogger.d(_tag, 'syncFromUI: no stats returned');
        return;
      }

      final dateStr = AppUsageModel.todayString();

      for (final entry in stats.entries) {
        if (entry.value <= 0) continue;
        // FIX: correct method is insertOrUpdateUsage(), not upsertAppUsage()
        // FIX: appLabel is a required named param — pass empty string here;
        //      AppLabelService.refreshTodayLabels() fills it in separately
        await DatabaseHelper.instance.insertOrUpdateUsage(AppUsageModel(
          packageName:  entry.key,
          appLabel:     '',          // filled by AppLabelService
          date:         dateStr,
          usageMinutes: entry.value,
        ));
      }

      await _checkLimits(dateStr);
      AppLogger.i(_tag, 'syncFromUI: ${stats.length} apps synced');
    } catch (e) {
      AppLogger.e(_tag, 'syncFromUI failed', e);
    }
  }

  // ── Sync from BGS tick ─────────────────────────────────────
  // Called by PhaseOut's BGS/Kotlin tick. Same logic, lighter logging.
  static Future<void> syncFromBgs() async {
    try {
      final now        = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day)
          .millisecondsSinceEpoch;
      final endMs      = now.millisecondsSinceEpoch;

      final stats = await UsageChannel.getStatsForRange(startOfDay, endMs);
      if (stats.isEmpty) return;

      final dateStr = AppUsageModel.todayString();

      for (final entry in stats.entries) {
        if (entry.value <= 0) continue;
        await DatabaseHelper.instance.insertOrUpdateUsage(AppUsageModel(
          packageName:  entry.key,
          appLabel:     '',
          date:         dateStr,
          usageMinutes: entry.value,
        ));
      }

      await _checkLimits(dateStr);
    } catch (e) {
      AppLogger.e(_tag, 'syncFromBgs failed', e);
    }
  }

  // ── Set a daily usage limit for an app ────────────────────
  static Future<void> setLimit(String packageName, int minutes) async {
    try {
      await DatabaseHelper.instance.setAppLimit(packageName, minutes);
      AppLogger.i(_tag, 'Limit set: $packageName → ${minutes}m');
    } catch (e) {
      AppLogger.e(_tag, 'setLimit failed', e);
    }
  }

  // ── Check all limits and notify if exceeded ───────────────
  // Private — called internally after every sync.
  // scheduler_service.dart should call syncFromBgs(), not this directly.
  static Future<void> _checkLimits(String dateStr) async {
    try {
      final usage = await DatabaseHelper.instance.getUsageForDate(dateStr);
      for (final app in usage) {
        if (app.isOverLimit) {
          await NotificationService.sendAlert(
            'Daily limit reached',
            '${app.appLabel.isNotEmpty ? app.appLabel : app.packageName} — '
            "you've hit your ${app.formattedLimit} limit for today.",
          );
        }
      }
    } catch (e) {
      AppLogger.e(_tag, '_checkLimits failed', e);
    }
  }
}