// ─────────────────────────────────────────────────────────────
//  lib/channels/usage_channel.dart
//  PhaseOut — Dart side of the usage MethodChannel bridge
//
//  ADDED:
//  - getAllInstalledApps() — every launchable app via PackageManager
//  - getForegroundApp()   — current foreground app (2s window)
// ─────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';
import '../utils/logger.dart';

class UsageChannel {

  static const String _tag = 'UsageChannel';
  static const MethodChannel _channel =
      MethodChannel('com.brightdev.phaseout/usage');

  UsageChannel._();

  // ── Get usage stats for a time range ─────────────────────
  static Future<Map<String, int>> getStatsForRange(
      int startMs, int endMs) async {
    try {
      final raw = await _channel.invokeMethod<Map>('getUsageStats',
          {'startMs': startMs, 'endMs': endMs});
      if (raw == null) return {};
      return raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } catch (e) {
      AppLogger.e(_tag, 'getStatsForRange error', e);
      return {};
    }
  }

  // ── Check usage access permission ─────────────────────────
  static Future<bool> hasUsagePermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasUsagePermission') ?? false;
    } catch (e) {
      AppLogger.e(_tag, 'hasUsagePermission error', e);
      return false;
    }
  }

  // ── Open usage access settings ────────────────────────────
  static Future<void> openUsageSettings() async {
    try {
      await _channel.invokeMethod<void>('openUsageSettings');
    } catch (e) {
      AppLogger.e(_tag, 'openUsageSettings error', e);
    }
  }

  // ── Get display label for a package ──────────────────────
  static Future<String> getAppLabel(String packageName) async {
    try {
      return await _channel.invokeMethod<String>(
              'getAppLabel', {'packageName': packageName}) ??
          packageName;
    } catch (e) {
      return packageName;
    }
  }

  // ── Get icon bytes for a package ──────────────────────────
  static Future<List<int>?> getAppIcon(String packageName) async {
    try {
      final bytes = await _channel.invokeMethod<List<int>>(
          'getAppIcon', {'packageName': packageName});
      return bytes;
    } catch (e) {
      return null;
    }
  }

  // ── Get ALL launchable installed apps ─────────────────────
  // Uses PackageManager.getInstalledApplications() filtered by
  // getLaunchIntentForPackage() != null — identical to how the
  // Android launcher builds the app drawer.
  //
  // Returns a list of {packageName, label} maps.
  // No usage stats permission required.
  // Icons are fetched separately via getAppIcon() to allow
  // progressive loading in the UI.
  static Future<List<AppInfo>> getAllInstalledApps() async {
    try {
      final raw = await _channel.invokeMethod<List>('getAllInstalledApps');
      if (raw == null) return [];
      return raw
          .whereType<Map>()
          .map((m) => AppInfo(
                packageName: m['packageName']?.toString() ?? '',
                label:       m['label']?.toString() ?? '',
              ))
          .where((a) => a.packageName.isNotEmpty)
          .toList();
    } catch (e) {
      AppLogger.e(_tag, 'getAllInstalledApps error', e);
      return [];
    }
  }

  // ── Get current foreground app (2-second window) ──────────
  // Much faster than the previous 7-day window approach.
  // Used by PhaseOutService focus polling every 1 second.
  static Future<String?> getForegroundApp() async {
    try {
      return await _channel.invokeMethod<String>('getForegroundApp');
    } catch (e) {
      AppLogger.e(_tag, 'getForegroundApp error', e);
      return null;
    }
  }
}

// ── Simple model for installed app info ───────────────────────
class AppInfo {
  final String packageName;
  final String label;
  const AppInfo({required this.packageName, required this.label});
}