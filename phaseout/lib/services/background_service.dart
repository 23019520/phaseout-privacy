// ─────────────────────────────────────────────────────────────
//  lib/services/background_service.dart
//  PhaseOut — Background service lifecycle manager
//
//  Manages the flutter_background_service persistent process.
//  The service runs in a SEPARATE DART ISOLATE — it cannot
//  access Flutter widget state or the main isolate directly.
//
//  Use AppLogger.bg() not AppLogger.d() inside _onStart.
//  Use ServiceInstance to communicate back to the UI isolate.
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'notification_service.dart';
import 'scheduler_service.dart';

class BackgroundService {

  static const String _tag = 'BackgroundService';

  BackgroundService._();

  // ── Initialise ────────────────────────────────────────────
  // Configures flutter_background_service.
  // Must be called from main() AFTER NotificationService.initialise().
  static Future<void> initialise() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart:           _onStart,
        isForegroundMode:  true,
        autoStart:         true,
        autoStartOnBoot:   true,
        foregroundServiceNotificationId: AppConstants.notifIdBGS,
        notificationChannelId: AppConstants.notifChannelBGS,
        initialNotificationTitle:   'PhaseOut is active',
        initialNotificationContent: 'Monitoring your schedules',
      ),
      iosConfiguration: IosConfiguration(
        autoStart:  true,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );

    AppLogger.i(_tag, 'BackgroundService initialised');
  }

  // ── iOS background handler ────────────────────────────────
  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    return true;
  }

  // ── Service entry point ───────────────────────────────────
  // Runs in a SEPARATE ISOLATE. Do not use AppLogger.d() here.
  // Do not access any widget or main isolate state here.
  @pragma('vm:entry-point')
  static Future<void> _onStart(ServiceInstance service) async {
    AppLogger.bg(_tag, 'Background service started');

    // Cast to Android instance for foreground-specific features
    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((_) {
        service.setAsForegroundService();
      });
      service.on('setAsBackground').listen((_) {
        service.setAsBackgroundService();
      });

      // Show the persistent foreground notification
      await NotificationService.showPersistentBGS();
    }

    // Listen for stop command from UI
    service.on('stopService').listen((_) {
      AppLogger.bg(_tag, 'Stop command received');
      service.stopSelf();
    });

    // Start the 60-second scheduler tick loop
    _startTickLoop(service);
  }

  // ── Tick loop ─────────────────────────────────────────────
  // Runs every 60 seconds inside the background isolate.
  // Calls SchedulerService.evaluate() on each tick.
  static void _startTickLoop(ServiceInstance service) {
    AppLogger.bg(_tag, 'Tick loop started — interval: ${AppConstants.bgTickIntervalSeconds}s');

    Timer.periodic(
  const Duration(seconds: AppConstants.bgTickIntervalSeconds),
    (timer) async {
        // Check if service is still running
        if (service is AndroidServiceInstance) {
          final isRunning = await service.isForegroundService();
          if (!isRunning) {
            AppLogger.bg(_tag, 'Service no longer foreground — stopping timer');
            timer.cancel();
            return;
          }
        }

        AppLogger.bg(_tag, 'Tick — evaluating schedules');

        try {
          await SchedulerService.evaluate();
        } catch (e) {
          AppLogger.bg(_tag, 'SchedulerService.evaluate() error: $e');
        }
      },
    );
  }

  // ── Public controls ───────────────────────────────────────

  // Returns true if the background service is currently running.
  static Future<bool> isRunning() async {
    return FlutterBackgroundService().isRunning();
  }

  // Starts the background service manually.
  static Future<void> start() async {
    AppLogger.i(_tag, 'Starting background service');
    await FlutterBackgroundService().startService();
  }

  // Sends a stop command to the background isolate.
  static Future<void> stop() async {
    AppLogger.i(_tag, 'Stopping background service');
    final service = FlutterBackgroundService();
    service.invoke('stopService');
    await NotificationService.cancelAll();
  }
}