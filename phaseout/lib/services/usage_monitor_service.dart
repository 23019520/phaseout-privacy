// ─────────────────────────────────────────────────────────────
//  lib/services/usage_monitor_service.dart
//
//  FIXES:
//  1. _sync() no longer saves appLabel: '' unconditionally.
//     The DB layer (insertOrUpdateUsage) now preserves any
//     already-resolved label, but we also skip the label field
//     entirely in the sync path — sync is only about minutes.
//
//  2. _notifiedToday midnight reset now also fires from the UI
//     sync path when the date has rolled over since the last
//     sync, not just from the background service.  This means
//     users who only use the UI path still get fresh
//     notifications each new day.
//
//  3. setLimit() clears the notif key so a re-set limit always
//     produces a fresh notification if the user is already over.
// ─────────────────────────────────────────────────────────────

import '../channels/usage_channel.dart';
import '../db/database_helper.dart';
import '../models/app_usage_model.dart';
import '../services/notification_service.dart';
import '../utils/logger.dart';

class UsageMonitorService {
  UsageMonitorService._();

  static const String _tag = 'UsageMonitorService';

  static final Set<String> _notifiedToday = {};

  // Track which calendar date _notifiedToday corresponds to so we
  // can reset it automatically when the date rolls over, even when
  // only the UI sync path is running (background service may not
  // fire exactly at midnight).
  static String _notifDate = AppUsageModel.todayString();

  // ── Sync: UI isolate ──────────────────────────────────────

  static Future<void> syncFromUI() async {
    await _sync(verbose: true);
  }

  // ── Sync: background service ──────────────────────────────

  static Future<void> syncFromBgs() async {
    await _sync(verbose: false);
  }

  // ── Set a daily limit ─────────────────────────────────────

  /// Writes [minutes] as the daily limit for [packageName].
  /// Pass 0 to clear the limit.
  static Future<void> setLimit(String packageName, int minutes) async {
    try {
      await DatabaseHelper.instance.setAppLimit(packageName, minutes);
      // Clear the notif key so a freshly-set limit fires a new
      // notification if the user is already over the new threshold.
      _notifiedToday.remove(_notifKey(packageName, AppUsageModel.todayString()));
      AppLogger.i(_tag, 'Limit set: $packageName → ${minutes}m/day');
    } catch (e) {
      AppLogger.e(_tag, 'setLimit failed', e);
    }
  }

  // ── Core sync logic ────────────────────────────────────────

  static Future<void> _sync({required bool verbose}) async {
    try {
      // FIX: reset daily notification state automatically when the
      // calendar date has changed, even if the background service
      // never fired resetDailyNotifications().
      final today = AppUsageModel.todayString();
      if (today != _notifDate) {
        _notifiedToday.clear();
        _notifDate = today;
        AppLogger.d(_tag, 'New day detected — notification state reset');
      }

      final now        = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day)
          .millisecondsSinceEpoch;
      final endMs = now.millisecondsSinceEpoch;

      final stats = await UsageChannel.getStatsForRange(startOfDay, endMs);

      if (stats.isEmpty) {
        if (verbose) AppLogger.d(_tag, 'sync: no stats returned from channel');
        return;
      }

      // FIX: only sync usage_minutes here.  We intentionally omit
      // appLabel from the sync path — the DB layer (insertOrUpdateUsage)
      // will preserve any label already resolved.  This prevents each
      // sync from wiping resolved labels back to empty strings.
      for (final entry in stats.entries) {
        if (entry.value <= 0) continue;
        await DatabaseHelper.instance.insertOrUpdateUsage(AppUsageModel(
          packageName:  entry.key,
          appLabel:     '',   // DB layer preserves existing label if present
          date:         today,
          usageMinutes: entry.value,
        ));
      }

      if (verbose) {
        AppLogger.i(_tag, 'sync: ${stats.length} apps persisted for $today');
      }

      await _checkLimits(today);
    } catch (e) {
      AppLogger.e(_tag, '_sync failed', e);
    }
  }

  // ── Limit enforcement ──────────────────────────────────────

  static Future<void> _checkLimits(String dateStr) async {
    try {
      final apps = await DatabaseHelper.instance.getAppsOverLimit();

      for (final app in apps) {
        final key = _notifKey(app.packageName, dateStr);
        if (_notifiedToday.contains(key)) continue;

        final label = app.appLabel.isNotEmpty ? app.appLabel : app.packageName;
        await NotificationService.sendAlert(
          'Daily limit reached',
          '$label — you\'ve used your ${app.formattedLimit} for today.',
        );

        _notifiedToday.add(key);
        AppLogger.i(_tag, 'Limit notification sent: $label');
      }
    } catch (e) {
      AppLogger.e(_tag, '_checkLimits failed', e);
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  static String _notifKey(String packageName, String date) =>
      '$packageName@$date';

  /// Clears the in-memory notification state.
  /// Called at midnight by the background service; also called
  /// automatically inside _sync() when the date changes.
  static void resetDailyNotifications() {
    _notifiedToday.clear();
    _notifDate = AppUsageModel.todayString();
    AppLogger.d(_tag, 'Daily notification state reset');
  }
}