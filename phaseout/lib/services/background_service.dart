// ─────────────────────────────────────────────────────────────
//  lib/services/background_service.dart
//  PhaseOut — Flutter background service (UI sync only)
//
//  PhaseOutService (Kotlin) owns all native calls and
//  schedule evaluation. This Flutter BGS only handles
//  DB sync tasks that need Dart (usage stats, battery).
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'notification_service.dart';
import 'scheduler_service.dart';

@pragma('vm:entry-point')
class BackgroundService {

  static const String _tag = 'BackgroundService';
  BackgroundService._();

  static Future<void> initialise() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart:           _onStart,
        isForegroundMode:  false, // PhaseOutService is the foreground one now
        autoStart:         true,
        autoStartOnBoot:   true,
        foregroundServiceNotificationId: AppConstants.notifIdBGS,
        notificationChannelId: AppConstants.notifChannelBGS,
        initialNotificationTitle:   'PhaseOut sync',
        initialNotificationContent: 'Syncing usage data',
      ),
      iosConfiguration: IosConfiguration(
        autoStart:    true,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );

    AppLogger.i(_tag, 'BackgroundService initialised');
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    return true;
  }

  @pragma('vm:entry-point')
  static Future<void> _onStart(ServiceInstance service) async {
    AppLogger.bg(_tag, 'Flutter BGS started (sync mode)');

    service.on('stopService').listen((_) {
      AppLogger.bg(_tag, 'Stop command received');
      service.stopSelf();
    });

    // Sync tick — usage data and battery only
    Timer.periodic(
      const Duration(seconds: AppConstants.bgTickIntervalSeconds),
      (timer) async {
        AppLogger.bg(_tag, 'Sync tick');
        try {
          await SchedulerService.evaluate();
        } catch (e) {
          AppLogger.bg(_tag, 'Sync error: $e');
        }
      },
    );
  }

  static Future<bool> isRunning() async =>
      FlutterBackgroundService().isRunning();

  static Future<void> start() async {
    AppLogger.i(_tag, 'Starting Flutter BGS');
    await FlutterBackgroundService().startService();
  }

  static Future<void> stop() async {
    AppLogger.i(_tag, 'Stopping Flutter BGS');
    FlutterBackgroundService().invoke('stopService');
    await NotificationService.cancelAll();
  }
}