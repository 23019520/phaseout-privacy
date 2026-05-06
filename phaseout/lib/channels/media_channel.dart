// ─────────────────────────────────────────────────────────────
//  lib/channels/media_channel.dart
//  PhaseOut — Dart side of the media MethodChannel bridge
//
//  ADDED this version:
//  - dimBrightness(int level)   → sets screen brightness 0-255
//  - restoreBrightness()        → restores to saved level
//  - enableDnd()                → programmatically enable DND
//  - disableDnd()               → programmatically disable DND
//  - sendChargeReminder()       → posts a low-battery/charge now
//                                 notification directly
//  - goHome()                   → sends HOME intent
//
//  Previously added:
//  - isNotificationListenerEnabled()
//  - isDndAccessGranted()
//  - isWriteSettingsGranted()
//  - openDndSettings()
//  - openWriteSettings()
// ─────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

class MediaChannel {

  static const String _tag = 'MediaChannel';

  MediaChannel._();

  static const MethodChannel _channel = MethodChannel(
    AppConstants.mediaChannel,
  );

  // ── Open notification listener settings ───────────────────
  static Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod<void>('openNotificationSettings');
    } catch (e) {
      AppLogger.e(_tag, 'openNotificationSettings error', e);
    }
  }

  // ── Check if notification listener is enabled ─────────────
  static Future<bool> isNotificationListenerEnabled() async {
    try {
      return await _channel.invokeMethod<bool>(
              'isNotificationListenerEnabled') ??
          false;
    } catch (e) {
      AppLogger.e(_tag, 'isNotificationListenerEnabled error', e);
      return false;
    }
  }

  // ── Check Do Not Disturb access ───────────────────────────
  static Future<bool> isDndAccessGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isDndAccessGranted') ?? false;
    } catch (e) {
      AppLogger.e(_tag, 'isDndAccessGranted error', e);
      return false;
    }
  }

  // ── Check write system settings access ────────────────────
  static Future<bool> isWriteSettingsGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isWriteSettingsGranted') ??
          false;
    } catch (e) {
      AppLogger.e(_tag, 'isWriteSettingsGranted error', e);
      return false;
    }
  }

  // ── Open Do Not Disturb access settings directly ──────────
  static Future<void> openDndSettings() async {
    try {
      await _channel.invokeMethod<void>('openDndSettings');
    } catch (e) {
      AppLogger.e(_tag, 'openDndSettings error', e);
    }
  }

  // ── Open modify system settings directly ──────────────────
  static Future<void> openWriteSettings() async {
    try {
      await _channel.invokeMethod<void>('openWriteSettings');
    } catch (e) {
      AppLogger.e(_tag, 'openWriteSettings error', e);
    }
  }

  // ── Open battery optimisation settings ────────────────────
  /// Opens the per-app battery optimisation toggle directly.
  /// permission_handler's request() is a no-op on most OEMs —
  /// this navigates the user to the correct Settings page.
  static Future<void> openBatterySettings() async {
    try {
      await _channel.invokeMethod<void>('openBatterySettings');
    } catch (e) {
      AppLogger.e(_tag, 'openBatterySettings error', e);
    }
  }

  // ── Open system alert window (overlay) settings ───────────
  /// Opens the per-app "Display over other apps" toggle.
  /// permission_handler's systemAlertWindow.request() is a
  /// no-op on Android 11+ — this opens the correct page.
  static Future<void> openOverlaySettings() async {
    try {
      await _channel.invokeMethod<void>('openOverlaySettings');
    } catch (e) {
      AppLogger.e(_tag, 'openOverlaySettings error', e);
    }
  }

  // ── Dim brightness ────────────────────────────────────────
  /// Sets screen brightness to [level] (0–255).
  /// Saves the current brightness first so restoreBrightness()
  /// can bring it back.
  /// Requires WRITE_SETTINGS permission — check
  /// isWriteSettingsGranted() before calling.
  static Future<bool> dimBrightness({int level = 30}) async {
    try {
      AppLogger.d(_tag, 'Calling dimBrightness level=$level');
      final result = await _channel.invokeMethod<bool>(
        'dimBrightness',
        {'level': level},
      );
      final success = result ?? false;
      AppLogger.i(_tag, 'dimBrightness result: $success');
      return success;
    } on PlatformException catch (e, st) {
      AppLogger.e(_tag, 'dimBrightness PlatformException: ${e.message}', e, st);
      return false;
    } catch (e, st) {
      AppLogger.e(_tag, 'dimBrightness unexpected error', e, st);
      return false;
    }
  }

  // ── Restore brightness ────────────────────────────────────
  /// Restores the brightness level saved before the last
  /// dimBrightness() call.
  static Future<bool> restoreBrightness() async {
    try {
      AppLogger.d(_tag, 'Calling restoreBrightness');
      final result = await _channel.invokeMethod<bool>('restoreBrightness');
      final success = result ?? false;
      AppLogger.i(_tag, 'restoreBrightness result: $success');
      return success;
    } on PlatformException catch (e, st) {
      AppLogger.e(_tag, 'restoreBrightness PlatformException: ${e.message}', e, st);
      return false;
    } catch (e, st) {
      AppLogger.e(_tag, 'restoreBrightness unexpected error', e, st);
      return false;
    }
  }

  // ── Enable Do Not Disturb ─────────────────────────────────
  /// Programmatically sets DND to INTERRUPTION_FILTER_NONE.
  /// Requires isDndAccessGranted() == true.
  static Future<bool> enableDnd() async {
    try {
      AppLogger.d(_tag, 'Calling enableDnd');
      final result = await _channel.invokeMethod<bool>('enableDnd');
      final success = result ?? false;
      AppLogger.i(_tag, 'enableDnd result: $success');
      return success;
    } on PlatformException catch (e, st) {
      AppLogger.e(_tag, 'enableDnd PlatformException: ${e.message}', e, st);
      return false;
    } catch (e, st) {
      AppLogger.e(_tag, 'enableDnd unexpected error', e, st);
      return false;
    }
  }

  // ── Disable Do Not Disturb ────────────────────────────────
  /// Restores DND to INTERRUPTION_FILTER_ALL (normal).
  static Future<bool> disableDnd() async {
    try {
      AppLogger.d(_tag, 'Calling disableDnd');
      final result = await _channel.invokeMethod<bool>('disableDnd');
      final success = result ?? false;
      AppLogger.i(_tag, 'disableDnd result: $success');
      return success;
    } on PlatformException catch (e, st) {
      AppLogger.e(_tag, 'disableDnd PlatformException: ${e.message}', e, st);
      return false;
    } catch (e, st) {
      AppLogger.e(_tag, 'disableDnd unexpected error', e, st);
      return false;
    }
  }

  // ── Send charge reminder notification ─────────────────────
  /// Posts a "Time to charge your phone" notification on the
  /// phaseout_alert channel. Does NOT require special perms
  /// beyond POST_NOTIFICATIONS.
  static Future<bool> sendChargeReminder() async {
    try {
      AppLogger.d(_tag, 'Calling sendChargeReminder');
      final result = await _channel.invokeMethod<bool>('sendChargeReminder');
      final success = result ?? false;
      AppLogger.i(_tag, 'sendChargeReminder result: $success');
      return success;
    } on PlatformException catch (e, st) {
      AppLogger.e(_tag, 'sendChargeReminder PlatformException: ${e.message}', e, st);
      return false;
    } catch (e, st) {
      AppLogger.e(_tag, 'sendChargeReminder unexpected error', e, st);
      return false;
    }
  }

  // ── Go to home screen ─────────────────────────────────────
  static Future<bool> goHome() async {
    try {
      AppLogger.d(_tag, 'Calling goHome');
      final result = await _channel.invokeMethod<bool>('goHome');
      final success = result ?? false;
      AppLogger.i(_tag, 'goHome result: $success');
      return success;
    } on PlatformException catch (e, st) {
      AppLogger.e(_tag, 'goHome PlatformException: ${e.message}', e, st);
      return false;
    } catch (e, st) {
      AppLogger.e(_tag, 'goHome unexpected error', e, st);
      return false;
    }
  }

  // ── Stop all active media sessions ────────────────────────
  static Future<bool> stopAllMedia() async {
    try {
      AppLogger.d(_tag, 'Calling stopAllMedia');
      final result = await _channel.invokeMethod<bool>(
        AppConstants.methodStopAllMedia,
      );
      final success = result ?? false;
      AppLogger.i(_tag, 'stopAllMedia result: $success');
      return success;
    } on PlatformException catch (e, st) {
      AppLogger.e(_tag, 'stopAllMedia PlatformException: ${e.message}', e, st);
      return false;
    } catch (e, st) {
      AppLogger.e(_tag, 'stopAllMedia unexpected error', e, st);
      return false;
    }
  }

  // ── Release audio focus ───────────────────────────────────
  static Future<bool> releaseAudioFocus() async {
    try {
      AppLogger.d(_tag, 'Calling releaseAudioFocus');
      final result = await _channel.invokeMethod<bool>(
        AppConstants.methodReleaseAudioFocus,
      );
      final success = result ?? false;
      AppLogger.i(_tag, 'releaseAudioFocus result: $success');
      return success;
    } on PlatformException catch (e, st) {
      AppLogger.e(
          _tag, 'releaseAudioFocus PlatformException: ${e.message}', e, st);
      return false;
    } catch (e, st) {
      AppLogger.e(_tag, 'releaseAudioFocus unexpected error', e, st);
      return false;
    }
  }

  // ── Launch an app by package name ─────────────────────────
  static Future<bool> launchApp(String packageName) async {
    try {
      AppLogger.d(_tag, 'Calling launchApp: $packageName');
      final result = await _channel.invokeMethod<bool>(
        AppConstants.methodLaunchApp,
        {'package': packageName},
      );
      final success = result ?? false;
      AppLogger.i(_tag, 'launchApp($packageName) result: $success');
      return success;
    } on PlatformException catch (e, st) {
      AppLogger.e(_tag, 'launchApp PlatformException: ${e.message}', e, st);
      return false;
    } catch (e, st) {
      AppLogger.e(_tag, 'launchApp unexpected error', e, st);
      return false;
    }
  }
}