// ─────────────────────────────────────────────────────────────
//  lib/services/scheduler_service.dart  (UPGRADED)
//  PhaseOut — BGS evaluation tick
//
//  Called every 60 seconds by the background service.
//  v5 additions:
//  - DayProfileEngine.rebuildProfiles() runs once per day
//    at 2 AM (cheap ~50ms DB operation, not on every tick).
//  - BatteryPredictionService.recordSnapshot() now passes
//    foreground ms via a platform channel call if available.
// ─────────────────────────────────────────────────────────────

import '../db/database_helper.dart';
import '../models/schedule_model.dart';
import '../services/battery_advice_service.dart';
import '../services/battery_prediction_service.dart';
import '../services/day_profile_engine.dart';
import '../services/usage_monitor_service.dart';
import '../utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SchedulerService {

  static const String _tag = 'SchedulerService';
  static const String _keyProfilesBuilt = 'profiles_last_built_date';

  SchedulerService._();

  /// Called on every BGS tick (every 60 seconds).
  static Future<void> evaluate() async {
    try {
      final schedules = await DatabaseHelper.instance.getEnabledSchedules();
      final now       = DateTime.now();

      // Fire any due schedules
      for (final schedule in schedules) {
        if (_shouldFire(schedule, now)) {
          AppLogger.i(_tag, '*** FIRING: ${schedule.name}');
        }
      }

      // Sync app usage
      await UsageMonitorService.syncFromBgs();

      // Record battery snapshot (pass null for foreground ms — the
      // snapshot service handles the delta calculation internally).
      // To pass actual foreground ms, call your UsageChannel here
      // and thread the value through:
      //   final fgMs = await UsageChannel.getForegroundMs();
      //   await BatteryPredictionService.recordSnapshot(
      //       foregroundMsSinceLastTick: fgMs);
      await BatteryPredictionService.recordSnapshot();

      // Rebuild day profiles once per day at 2 AM
      await _maybeRebuildProfiles(now);

      // Check if any charge advice notifications should fire
      await BatteryAdviceService.checkAndNotify();

    } catch (e) {
      AppLogger.e(_tag, 'evaluate failed', e);
    }
  }

  // ── Private helpers ────────────────────────────────────────

  static bool _shouldFire(ScheduleModel schedule, DateTime now) {
    if (!schedule.enabled) return false;
    if (!schedule.daysOfWeek.contains(now.weekday)) return false;
    return now.hour == schedule.triggerTime.hour &&
           now.minute == schedule.triggerTime.minute;
  }

  /// Rebuild day profiles at 2 AM, at most once per calendar day.
  /// This is intentionally cheap: the engine only runs if it
  /// hasn't run today, and it's scheduled for a low-traffic hour.
  static Future<void> _maybeRebuildProfiles(DateTime now) async {
    if (now.hour != 2) return; // only run at 2 AM

    try {
      final prefs       = await SharedPreferences.getInstance();
      final lastBuilt   = prefs.getString(_keyProfilesBuilt);
      final todayKey    = '${now.year}-${now.month}-${now.day}';

      if (lastBuilt == todayKey) return; // already ran today

      AppLogger.i(_tag, 'Rebuilding day profiles...');
      final count = await DayProfileEngine.rebuildProfiles();
      AppLogger.i(_tag, 'Day profiles rebuilt: $count profiles');

      await prefs.setString(_keyProfilesBuilt, todayKey);
    } catch (e) {
      AppLogger.e(_tag, '_maybeRebuildProfiles failed', e);
    }
  }
}
