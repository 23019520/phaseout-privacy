// ─────────────────────────────────────────────────────────────
//  lib/services/scheduler_service.dart
//  PhaseOut — Schedule evaluation and action dispatch
//
//  Called every 60 seconds by BackgroundService tick loop.
//  Reads enabled schedules from DB, checks time/day match,
//  and dispatches actions for matched schedules.
//
//  Runs inside the background isolate — use AppLogger.bg().
// ─────────────────────────────────────────────────────────────

import '../db/database_helper.dart';
import '../models/schedule_model.dart';
import '../models/usage_event_model.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import '../utils/time_utils.dart';
import '../channels/media_channel.dart';
import 'notification_service.dart';
import 'usage_monitor_service.dart';

class SchedulerService {

  static const String _tag = 'SchedulerService';

  SchedulerService._();

  // Tracks last fired time per schedule ID to prevent double-firing
  // within the same minute window. Stored in memory only.
  static final Map<int, DateTime> _lastFired = {};

  // ── Main evaluation entry point ───────────────────────────
  // Called every 60 seconds by the BGS tick loop.
  static Future<void> evaluate() async {
  AppLogger.bg(_tag, 'Evaluating schedules');

  List<ScheduleModel> schedules;

  try {
    schedules = await DatabaseHelper.instance.getEnabledSchedules();
  } catch (e) {
    AppLogger.bg(_tag, 'Failed to load schedules: $e');
    return;
  }

  if (schedules.isEmpty) {
    AppLogger.bg(_tag, 'No enabled schedules found');
  } else {
    AppLogger.bg(_tag, 'Checking ${schedules.length} enabled schedule(s)');
    for (final schedule in schedules) {
      await _checkSchedule(schedule);
    }
  }

  // ── Sprint 2: check app usage limits on every tick ────────
  await UsageMonitorService.checkLimits();
}

  // ── Check a single schedule ───────────────────────────────
  static Future<void> _checkSchedule(ScheduleModel schedule) async {
    if (!TimeUtils.isMatchNow(schedule)) return;

    // Guard: prevent firing twice in the same minute
    if (_alreadyFiredThisMinute(schedule)) {
      AppLogger.bg(_tag, 'Schedule ${schedule.id} already fired this minute — skipping');
      return;
    }

    AppLogger.bg(_tag, 'Schedule matched: ${schedule.name} at ${schedule.formattedTime}');

    // Record the fire time
    _lastFired[schedule.id!] = DateTime.now();

    // Dispatch all actions
    await _dispatch(schedule);
  }

  // ── Dispatch actions ──────────────────────────────────────
  static Future<void> _dispatch(ScheduleModel schedule) async {
    for (final action in schedule.actions) {
      AppLogger.bg(_tag, 'Dispatching action: $action for schedule ${schedule.id}');

      String outcome = AppConstants.outcomeSuccess;

      try {
        switch (action) {
          case AppConstants.actionStopMedia:
            await _handleStopMedia(schedule);
            break;
          case AppConstants.actionSendNotification:
            await _handleSendNotification();
            break;
          case AppConstants.actionLaunchApp:
            // Sprint 2 — package name stored in schedule params
            AppLogger.bg(_tag, 'launchApp action — deferred to Sprint 2');
            break;
          case AppConstants.actionActivateFocus:
            // Sprint 3 — focus mode
            AppLogger.bg(_tag, 'activateFocus action — deferred to Sprint 3');
            break;
          default:
            AppLogger.bg(_tag, 'Unknown action: $action');
            outcome = AppConstants.outcomeSkipped;
        }
      } catch (e) {
        AppLogger.bg(_tag, 'Action $action failed: $e');
        outcome = AppConstants.outcomeFailed;
      }

      // Log every action to the audit trail
      await _logEvent(schedule, action, outcome);
    }
  }

  // ── Action handlers ───────────────────────────────────────

  static Future<void> _handleStopMedia(ScheduleModel schedule) async {
    AppLogger.bg(_tag, 'Stopping media for schedule: ${schedule.name}');

    // Call both — stopAllMedia handles MediaSession apps,
    // releaseAudioFocus handles Spotify and audio-focus-respecting apps
    final stopped = await MediaChannel.stopAllMedia();
    final focused = await MediaChannel.releaseAudioFocus();

    AppLogger.bg(_tag, 'stopAllMedia: $stopped, releaseAudioFocus: $focused');
  }

  static Future<void> _handleSendNotification() async {
    AppLogger.bg(_tag, 'Sending wind-down notification');
    await NotificationService.sendWindDownNotification();
  }

  // ── Double-fire guard ─────────────────────────────────────
  // Returns true if this schedule already fired within the last 90 seconds.
  // 90 seconds covers the 60-second tick interval with 30 seconds of margin.
  static bool _alreadyFiredThisMinute(ScheduleModel schedule) {
    final lastFire = _lastFired[schedule.id];
    if (lastFire == null) return false;
    final diff = DateTime.now().difference(lastFire).inSeconds;
    return diff < 90;
  }

  // ── Event logging ─────────────────────────────────────────
  static Future<void> _logEvent(
    ScheduleModel schedule,
    String action,
    String outcome,
  ) async {
    try {
      final event = UsageEventModel.actionFired(
        scheduleId: schedule.id!,
        action:     action,
        outcome:    outcome,
      );
      await DatabaseHelper.instance.insertUsageEvent(event);
      AppLogger.bg(_tag, 'Event logged: $action → $outcome');
    } catch (e) {
      AppLogger.bg(_tag, 'Failed to log event: $e');
    }
  }
}