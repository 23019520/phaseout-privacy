// ─────────────────────────────────────────────────────────────
//  lib/channels/usage_channel.dart
//  PhaseOut — Dart side of the usage stats MethodChannel bridge
//
//  Wraps raw MethodChannel calls to UsageStatsManager.
//  No other file should call this channel directly.
//
//  IMPORTANT: PACKAGE_USAGE_STATS is a signature-level permission.
//  The user must grant it manually in Settings → Apps →
//  Special App Access → Usage Access.
//  Call hasUsagePermission() before calling getUsageStats().
//
//  Usage:
//    final granted = await UsageChannel.hasUsagePermission();
//    if (!granted) await UsageChannel.openUsageSettings();
//    final stats = await UsageChannel.getUsageStats(startMs, endMs);
// ─────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

class UsageChannel {

  static const String _tag = 'UsageChannel';

  UsageChannel._();

  static const MethodChannel _channel = MethodChannel(
    AppConstants.usageChannel,
  );

  // ── Get usage stats for a time window ─────────────────────
  // Returns a map of packageName → foreground minutes.
  // startMs and endMs are milliseconds since epoch.
  // Returns empty map on error or if permission not granted.
  static Future<Map<String, int>> getUsageStats({
    required int startMs,
    required int endMs,
  }) async {
    try {
      AppLogger.d(_tag, 'Fetching usage stats');
      final result = await _channel.invokeMethod<Map>(
        AppConstants.methodGetUsageStats,
        {'startMs': startMs, 'endMs': endMs},
      );

      if (result == null) return {};

      // Cast from Map<Object?, Object?> to Map<String, int>
      final stats = <String, int>{};
      result.forEach((key, value) {
        if (key is String && value is int) {
          stats[key] = value;
        }
      });

      AppLogger.i(_tag, 'Got usage stats for ${stats.length} apps');
      return stats;

    } on PlatformException catch (e, st) {
      AppLogger.e(_tag, 'getUsageStats PlatformException: ${e.message}', e, st);
      return {};
    } catch (e, st) {
      AppLogger.e(_tag, 'getUsageStats unexpected error', e, st);
      return {};
    }
  }

  // ── Convenience: get today's usage stats ──────────────────
  // Uses midnight today as start and now as end.
  static Future<Map<String, int>> getTodayStats() async {
    final now   = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return getUsageStats(
      startMs: start.millisecondsSinceEpoch,
      endMs:   now.millisecondsSinceEpoch,
    );
  }

  // ── Check if permission is granted ────────────────────────
  // Returns true if PACKAGE_USAGE_STATS has been granted.
  // Called before getUsageStats() to avoid silent failures.
  static Future<bool> hasUsagePermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasUsagePermission');
      final granted = result ?? false;
      AppLogger.d(_tag, 'Usage permission granted: $granted');
      return granted;
    } on PlatformException catch (e, st) {
      AppLogger.e(_tag, 'hasUsagePermission error', e, st);
      return false;
    }
  }

  // ── Open usage access settings ────────────────────────────
  // Opens Settings → Apps → Special App Access → Usage Access.
  // The user must manually enable PhaseOut in that screen.
  static Future<void> openUsageSettings() async {
    try {
      AppLogger.i(_tag, 'Opening usage access settings');
      await _channel.invokeMethod<void>('openUsageSettings');
    } on PlatformException catch (e, st) {
      AppLogger.e(_tag, 'openUsageSettings error', e, st);
    }
  }
}