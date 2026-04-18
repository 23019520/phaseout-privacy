// ─────────────────────────────────────────────────────────────
//  lib/services/battery_service.dart
//  PhaseOut — Battery monitoring and snapshot recording
//
//  Polls battery level and charging state every 5 minutes.
//  Writes BatterySnapshotModel to DB for ML training data.
//  Also triggers low battery notifications.
//
//  Runs inside the background isolate — use AppLogger.bg().
// ─────────────────────────────────────────────────────────────

import 'package:battery_plus/battery_plus.dart';
import '../db/database_helper.dart';
import '../models/battery_snapshot_model.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

class BatteryService {

  static const String _tag = 'BatteryService';

  BatteryService._();

  static final Battery _battery = Battery();

  // Tracks last snapshot time to enforce 5-minute poll interval
  static DateTime? _lastSnapshot;

  // Tracks last low battery notification to prevent spam
  static DateTime? _lastLowNotification;

  // ── Main entry point — called by BGS tick ────────────────
  // Respects the 5-minute poll interval.
  static Future<void> recordSnapshot() async {
    final now = DateTime.now();

    // Only record every 5 minutes
    if (_lastSnapshot != null) {
      final diff = now.difference(_lastSnapshot!).inSeconds;
      if (diff < AppConstants.batteryPollIntervalSeconds) {
        return;
      }
    }

    await _captureAndStore(now);
  }

  // ── Capture battery state and write to DB ─────────────────
  static Future<void> _captureAndStore(DateTime now) async {
    try {
      final level  = await _battery.batteryLevel;
      final state  = await _battery.batteryState;
      final charging = state == BatteryState.charging ||
                       state == BatteryState.full;

      final snapshot = BatterySnapshotModel(
        recordedAt: now,
        level:      level,
        charging:   charging,
        dayOfWeek:  now.weekday,
      );

      await DatabaseHelper.instance.insertBatterySnapshot(snapshot);
      _lastSnapshot = now;

      AppLogger.bg(_tag,
        'Snapshot: $level% charging=$charging day=${snapshot.dayName}');

      // Check for low battery and notify if needed
      await _checkLowBattery(level, charging);

    } catch (e) {
      AppLogger.bg(_tag, 'Failed to capture battery snapshot: $e');
    }
  }

  // ── Low battery notification ──────────────────────────────
  static Future<void> _checkLowBattery(int level, bool charging) async {
    if (charging) return;
    if (level >= 20) return;

    // Only notify once per hour
    if (_lastLowNotification != null) {
      final diff = DateTime.now()
          .difference(_lastLowNotification!)
          .inMinutes;
      if (diff < 60) return;
    }

    _lastLowNotification = DateTime.now();

    final title = level < 10 ? 'Critical battery' : 'Low battery';
    final body  = 'Battery is at $level%. '
        '${level < 10 ? 'Charge now to avoid shutdown.' : 'Consider charging soon.'}';

    await NotificationService.sendScheduledReminder(title, body);
    AppLogger.bg(_tag, 'Low battery notification sent: $level%');
  }

  // ── Get current battery level (called from UI) ────────────
  static Future<int> getCurrentLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (e) {
      AppLogger.e(_tag, 'Failed to get battery level', e);
      return -1;
    }
  }

  // ── Get current charging state (called from UI) ───────────
  static Future<bool> isCharging() async {
    try {
      final state = await _battery.batteryState;
      return state == BatteryState.charging || state == BatteryState.full;
    } catch (e) {
      AppLogger.e(_tag, 'Failed to get charging state', e);
      return false;
    }
  }

  // ── Get recent snapshots (called from MLEngine) ───────────
  static Future<List<BatterySnapshotModel>> getRecentSnapshots({
    int days = 28,
  }) async {
    return DatabaseHelper.instance.getBatterySnapshots(days: days);
  }
}
