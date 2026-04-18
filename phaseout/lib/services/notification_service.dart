// ─────────────────────────────────────────────────────────────
//  lib/services/notification_service.dart
//  PhaseOut — Notification channels with sound (IMPORTANCE_HIGH)
// ─────────────────────────────────────────────────────────────

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

class NotificationService {

  static const String _tag = 'NotificationService';
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  NotificationService._();

  static Future<void> initialise() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings,
        onDidReceiveNotificationResponse: _onTap);
    await _createChannels();
    AppLogger.i(_tag, 'NotificationService initialised');
  }

  static void _onTap(NotificationResponse r) =>
      AppLogger.d(_tag, 'Notification tapped: ${r.id}');

  static Future<void> _createChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    // Silent BGS persistent
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        AppConstants.notifChannelBGS,
        AppConstants.notifChannelBGSName,
        description: 'Keeps PhaseOut running overnight',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    );

    // Wind-down — HIGH with sound
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        AppConstants.notifChannelWindDown,
        AppConstants.notifChannelWindDownName,
        description: 'Bedtime schedule alerts',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      ),
    );

    // Reminders — HIGH with sound
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        AppConstants.notifChannelReminder,
        AppConstants.notifChannelReminderName,
        description: 'Upcoming schedule reminders',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    // General alerts — HIGH with sound
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        AppConstants.notifChannelAlert,
        AppConstants.notifChannelAlertName,
        description: 'Usage and focus alerts',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    // Usage limit alerts — HIGH with sound
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        AppConstants.notifChannelUsageAlert,
        AppConstants.notifChannelUsageAlertName,
        description: 'Daily app usage limit alerts',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    AppLogger.i(_tag, 'Notification channels created (IMPORTANCE_HIGH)');
  }

  static Future<void> showPersistentBGS() async {
    const details = AndroidNotificationDetails(
      AppConstants.notifChannelBGS, AppConstants.notifChannelBGSName,
      importance: Importance.low, priority: Priority.low,
      ongoing: true, autoCancel: false,
      playSound: false, enableVibration: false,
      icon: '@mipmap/ic_launcher',
    );
    await _plugin.show(AppConstants.notifIdBGS,
        'PhaseOut is active', 'Monitoring your schedules',
        const NotificationDetails(android: details));
  }

  static Future<void> sendWindDownNotification() async {
    const details = AndroidNotificationDetails(
      AppConstants.notifChannelWindDown, AppConstants.notifChannelWindDownName,
      importance: Importance.high, priority: Priority.high,
      playSound: true, enableVibration: true,
      icon: '@mipmap/ic_launcher',
      fullScreenIntent: true,
    );
    await _plugin.show(AppConstants.notifIdWindDown,
        'Wind-down time 🌙', 'Your bedtime schedule has started.',
        const NotificationDetails(android: details));
    AppLogger.i(_tag, 'Wind-down notification sent');
  }

  static Future<void> sendScheduledReminder(String title, String body) async {
    const details = AndroidNotificationDetails(
      AppConstants.notifChannelReminder, AppConstants.notifChannelReminderName,
      importance: Importance.high, priority: Priority.high,
      playSound: true, enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );
    await _plugin.show(AppConstants.notifIdReminder, title, body,
        const NotificationDetails(android: details));
    AppLogger.d(_tag, 'Reminder sent: $title');
  }

  static Future<void> sendAlert(String title, String body) async {
    const details = AndroidNotificationDetails(
      AppConstants.notifChannelAlert, AppConstants.notifChannelAlertName,
      importance: Importance.high, priority: Priority.high,
      playSound: true, enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );
    await _plugin.show(AppConstants.notifIdAlert, title, body,
        const NotificationDetails(android: details));
  }

  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
    AppLogger.i(_tag, 'All notifications cancelled');
  }

  static Future<void> cancel(int id) async => _plugin.cancel(id);
}