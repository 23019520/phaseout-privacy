// ─────────────────────────────────────────────────────────────
//  lib/channels/media_channel.dart
//  PhaseOut — Dart side of the media MethodChannel bridge
//
//  Wraps raw MethodChannel calls in typed, named functions.
//  No other file should ever call MethodChannel directly for
//  media operations — always go through this class.
//
//  Usage:
//    final stopped = await MediaChannel.stopAllMedia();
//    if (!stopped) AppLogger.w('Scheduler', 'Media stop failed');
// ─────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

class MediaChannel {

  static const String _tag = 'MediaChannel';

  MediaChannel._(); // prevent instantiation

  // The MethodChannel — name must match MainActivity.kt exactly
  static const MethodChannel _channel = MethodChannel(
    AppConstants.mediaChannel,
  );

  static Future<void> openNotificationSettings() async {
  try {
    await _channel.invokeMethod<void>('openNotificationSettings');
  } catch (e) {
    AppLogger.e(_tag, 'openNotificationSettings error', e);
  }
}

  // ── Stop all active media sessions ────────────────────────
  // Sends ACTION_STOP to every active MediaSession on the device.
  // Returns true if the native call succeeded.
  // Returns false on error — never throws.
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
  // Causes well-behaved media apps to pause when focus is lost.
  // Used by the audio sleep timer on expiry.
  // Returns true if the native call succeeded.
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
      AppLogger.e(_tag, 'releaseAudioFocus PlatformException: ${e.message}', e, st);
      return false;
    } catch (e, st) {
      AppLogger.e(_tag, 'releaseAudioFocus unexpected error', e, st);
      return false;
    }
  }

  // ── Launch an app by package name ─────────────────────────
  // Used by the App Scheduler feature to open an app at a set time.
  // Returns false if the app is not installed on the device.
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