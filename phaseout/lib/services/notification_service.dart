// ─────────────────────────────────────────────────────────────
//  lib/services/notification_service.dart
//  PhaseOut — Centralised notification management
//
//  All notification channels and notification types are defined
//  here. No other file should call flutter_local_notifications
//  directly — always go through NotificationService.
//
//  Call NotificationService.initialise() from main() BEFORE
//  BackgroundService.initialise().
// ─────────────────────────────────────────────────────────────

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

class NotificationService {

  static const String _tag = 'NotificationService';

  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialised = false;

  // ── Initialise ────────────────────────────────────────────
  // Creates all notification channels.
  // Requests POST_NOTIFICATIONS permission on Android 13+.
  // Must be called before BackgroundService.initialise().
  static Future<void> initialise() async {
    if (_initialised) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    await _createChannels();
    await _requestPermission();

    _initialised = true;
    AppLogger.i(_tag, 'NotificationService initialised');
  }

  // ── Create notification channels ──────────────────────────
  static Future<void> _createChannels() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return;

    // Persistent BGS channel — low importance so it doesn't make noise
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        AppConstants.notifChannelBGS,
        AppConstants.notifChannelBGSName,
        description: 'Keeps PhaseOut running in the background',
        importance: Importance.low,
        showBadge: false,
        playSound: false,
        enableVibration: false,
      ),
    );

    // Wind-down channel — high importance for heads-up display
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        AppConstants.notifChannelWindDown,
        AppConstants.notifChannelWindDownName,
        description: 'Sleep wind-down alerts',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    // Reminder channel — default importance
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        AppConstants.notifChannelReminder,
        AppConstants.notifChannelReminderName,
        description: 'Schedule and routine reminders',
        importance: Importance.defaultImportance,
      ),
    );

    // Alert channel — high importance for urgent alerts
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        AppConstants.notifChannelAlert,
        AppConstants.notifChannelAlertName,
        description: 'Usage limit and data alerts',
        importance: Importance.high,
      ),
    );

    await androidPlugin.createNotificationChannel(
  const AndroidNotificationChannel(
    AppConstants.notifChannelUsageAlert,
    AppConstants.notifChannelUsageAlertName,
    description: 'Daily app usage limit alerts',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  ),
);

    AppLogger.i(_tag, 'Notification channels created');
  }

  // ── Request permission (Android 13+) ──────────────────────
  static Future<void> _requestPermission() async {
    final status = await Permission.notification.status;
    if (status.isDenied) {
      final result = await Permission.notification.request();
      AppLogger.i(_tag, 'Notification permission result: $result');
    }
  }

  // ── Notification tap handler ──────────────────────────────
  static void _onNotificationTap(NotificationResponse response) {
    AppLogger.d(_tag, 'Notification tapped: ${response.id}');
    // Navigation handling added in Sprint 3
  }

  // ── Show persistent BGS notification ─────────────────────
  // This notification keeps the foreground service alive.
  // It cannot be dismissed by the user while BGS is running.
  static Future<void> showPersistentBGS() async {
    const androidDetails = AndroidNotificationDetails(
      AppConstants.notifChannelBGS,
      AppConstants.notifChannelBGSName,
      channelDescription: 'Keeps PhaseOut running in the background',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,           // cannot be dismissed
      autoCancel: false,
      showWhen: false,
      icon: '@mipmap/ic_launcher',
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      AppConstants.notifIdBGS,
      'PhaseOut is active',
      'Monitoring your schedules in the background',
      details,
    );

    AppLogger.i(_tag, 'Persistent BGS notification shown');
  }

  // ── Send wind-down notification ───────────────────────────
  // Sent when a sleep wind-down schedule fires.
  static Future<void> sendWindDownNotification() async {
    const androidDetails = AndroidNotificationDetails(
      AppConstants.notifChannelWindDown,
      AppConstants.notifChannelWindDownName,
      channelDescription: 'Sleep wind-down alerts',
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
      icon: '@mipmap/ic_launcher',
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      AppConstants.notifIdWindDown,
      'Good night 🌙',
      'PhaseOut has stopped your media. Sleep well.',
      details,
    );

    AppLogger.i(_tag, 'Wind-down notification sent');
  }

  // ── Send generic scheduled reminder ──────────────────────
  static Future<void> sendScheduledReminder(
    String title,
    String body,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      AppConstants.notifChannelReminder,
      AppConstants.notifChannelReminderName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      autoCancel: true,
      icon: '@mipmap/ic_launcher',
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      AppConstants.notifIdReminder,
      title,
      body,
      details,
    );

    AppLogger.i(_tag, 'Reminder sent: $title');
  }

  // ── Cancel all notifications ──────────────────────────────
  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
    AppLogger.i(_tag, 'All notifications cancelled');
  }

  // ── Cancel specific notification ──────────────────────────
  static Future<void> cancel(int id) async {
    await _plugin.cancel(id);
    AppLogger.i(_tag, 'Notification $id cancelled');
  }
}