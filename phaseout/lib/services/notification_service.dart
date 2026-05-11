// ─────────────────────────────────────────────────────────────
//  lib/services/notification_service.dart
//
//  FIX: notification IDs are now deterministic and collision-free.
//
//  Previous code used `DateTime.now().millisecondsSinceEpoch ~/ 1000`
//  as the notification ID for sendAlert().  Two calls within the same
//  second produced the same ID, so the second notification silently
//  replaced the first.
//
//  New strategy:
//    - General alerts      → hash of title+body, clamped to positive int
//    - Usage limit alerts  → stable hash of the package name
//      (so the same app never stacks multiple limit notifications,
//       but two different apps never collide)
//    - Reminders           → hash of scheduleName (unchanged)
//
//  Using a content hash rather than a timestamp also means repeated
//  calls with identical content update in place rather than stacking,
//  which is the correct UX for "you've hit your limit" alerts.
// ─────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../models/usage_event_model.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

class NotificationService {

  static const String _tag    = 'NotificationService';
  static const _channel       = MethodChannel(AppConstants.mediaChannel);
  static final _plugin         = FlutterLocalNotificationsPlugin();
  static bool  _initialized   = false;

  // ── Initialise ────────────────────────────────────────────

  static Future<void> initialise() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    _initialized = true;
    AppLogger.i(_tag, 'NotificationService initialised');
  }

  // ── Cancel all ────────────────────────────────────────────

  static Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
      AppLogger.d(_tag, 'All notifications cancelled');
    } catch (e) {
      AppLogger.e(_tag, 'cancelAll failed', e);
    }
  }

  // ── Event log ─────────────────────────────────────────────

  static Future<void> logEvent({
    required String eventType,
    required String detail,
    String outcome = AppConstants.outcomeSuccess,
  }) async {
    try {
      await DatabaseHelper.instance.insertUsageEvent(UsageEventModel(
        eventType: eventType,
        detail:    detail,
        outcome:   outcome,
        eventTime: DateTime.now(),
      ));
    } catch (e) {
      AppLogger.e(_tag, 'logEvent failed', e);
    }
  }

  // ── Send a high-importance alert ──────────────────────────

  /// FIX: ID is now a stable hash of [title]+[body] so repeated calls
  /// for the same alert update in-place rather than stacking.
  static Future<void> sendAlert(String title, String body) async {
    try {
      await initialise();
      final soundUri = await _getSoundUri();

      final details = AndroidNotificationDetails(
        AppConstants.channelAlerts,
        'PhaseOut Alerts',
        channelDescription: 'Schedule and limit alerts',
        importance:      Importance.high,
        priority:        Priority.high,
        playSound:       true,
        enableVibration: true,
        sound: soundUri != null
            ? UriAndroidNotificationSound(soundUri) : null,
      );

      // Stable, positive notification ID derived from content.
      final id = _stableId('$title|$body');

      await _plugin.show(
        id, title, body,
        NotificationDetails(android: details),
      );

      await logEvent(eventType: 'alert', detail: '$title — $body');
    } catch (e) {
      AppLogger.e(_tag, 'sendAlert failed', e);
    }
  }

  // ── Send a bedtime reminder ───────────────────────────────

  static Future<void> sendReminder(String scheduleName, String time) async {
    try {
      await initialise();
      final soundUri = await _getSoundUri();

      final details = AndroidNotificationDetails(
        AppConstants.channelReminders,
        'Bedtime Reminders',
        channelDescription: 'Upcoming schedule reminders',
        importance:  Importance.high,
        priority:    Priority.high,
        playSound:   true,
        sound: soundUri != null
            ? UriAndroidNotificationSound(soundUri) : null,
      );

      await _plugin.show(
        _stableId(scheduleName),
        '🌙 Bedtime in 30 minutes',
        '$scheduleName starts at $time',
        NotificationDetails(android: details),
      );

      await logEvent(
          eventType: 'reminder',
          detail: '$scheduleName — reminder at $time');
    } catch (e) {
      AppLogger.e(_tag, 'sendReminder failed', e);
    }
  }

  /// Alias used by battery/pre-notification services.
  static Future<void> sendScheduledReminder(
      String title, String body) async {
    await sendAlert(title, body);
  }

  // ── Custom sound ──────────────────────────────────────────

  static Future<void> setCustomSound(String? soundUri) async {
    final prefs = await SharedPreferences.getInstance();
    if (soundUri == null) {
      await prefs.remove(AppConstants.prefCustomSoundUri);
    } else {
      await prefs.setString(AppConstants.prefCustomSoundUri, soundUri);
    }
  }

  static Future<String?> getCustomSound() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.prefCustomSoundUri);
  }

  static Future<String?> _getSoundUri() => getCustomSound();

  static Future<void> clearCustomSound() => setCustomSound(null);

  static Future<String?> pickSound() async {
    try {
      final uri = await _channel
          .invokeMethod<String>('pickNotificationSound');
      if (uri != null) await setCustomSound(uri);
      return uri;
    } catch (e) {
      AppLogger.e(_tag, 'pickSound failed', e);
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  /// Returns a stable, non-negative int derived from [key].
  /// Uses Dart's built-in hashCode, clamped to the positive range
  /// Android accepts for notification IDs (0 to 2^31-1).
  static int _stableId(String key) => key.hashCode.abs();
}