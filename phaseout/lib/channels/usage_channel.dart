// ─────────────────────────────────────────────────────────────
//  lib/channels/usage_channel.dart
//  PhaseOut — Usage stats MethodChannel bridge (Dart side)
//
//  Main isolate only. Do NOT call from BGS isolate directly —
//  use BgsBridge methods instead.
// ─────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

class UsageChannel {

  static const String _tag = 'UsageChannel';
  UsageChannel._();

  static const MethodChannel _channel =
      MethodChannel(AppConstants.usageChannel);

  // ── Permission check ──────────────────────────────────────
  static Future<bool> hasUsagePermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasUsagePermission');
      return result ?? false;
    } on PlatformException catch (e) {
      AppLogger.e(_tag, 'hasUsagePermission failed', e);
      return false;
    }
  }

  // ── Open usage settings ───────────────────────────────────
  static Future<void> openUsageSettings() async {
    try {
      await _channel.invokeMethod('openUsageSettings');
    } on PlatformException catch (e) {
      AppLogger.e(_tag, 'openUsageSettings failed', e);
    }
  }

  // ── Get today's usage stats ───────────────────────────────
  // Returns packageName → minutes for the full day so far.
  static Future<Map<String, int>> getTodayStats() async {
    try {
      final now     = DateTime.now();
      final startMs = DateTime(now.year, now.month, now.day)
          .millisecondsSinceEpoch;
      return await getStatsForRange(startMs, now.millisecondsSinceEpoch);
    } on PlatformException catch (e) {
      AppLogger.e(_tag, 'getTodayStats failed', e);
      return {};
    }
  }

  // ── Get usage stats for an arbitrary time range ───────────
  // Used by BgsBridge.getForegroundApp() with a 10-second window.
  static Future<Map<String, int>> getStatsForRange(
    int startMs,
    int endMs,
  ) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getUsageStats',
        {'startMs': startMs, 'endMs': endMs},
      );

      if (raw == null) return {};

      final result = <String, int>{};
      raw.forEach((k, v) => result[k] = (v as num).toInt());
      return result;
    } on PlatformException catch (e) {
      AppLogger.e(_tag, 'getStatsForRange failed', e);
      return {};
    }
  }

  // ── Get app label ─────────────────────────────────────────
  static Future<String> getAppLabel(String packageName) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'getAppLabel',
        {'packageName': packageName},
      );
      return result ?? packageName;
    } on PlatformException catch (e) {
      AppLogger.e(_tag, 'getAppLabel($packageName) failed', e);
      return packageName;
    }
  }
}