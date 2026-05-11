// ─────────────────────────────────────────────────────────────
//  lib/channels/usage_channel.dart
//  PhaseOut — Dart ↔ Kotlin MethodChannel bridge (usage API)
//
//  All calls go through the single 'com.brightdev.phaseout/usage'
//  channel. The Kotlin side (MainActivity.setupUsageChannel) owns
//  every native implementation — this file is strictly a typed,
//  error-safe wrapper with no business logic of its own.
//
//  App list caching:
//    getAllInstalledApps() caches its result in memory for the
//    lifetime of the app process. The list never changes during
//    a session (installs/uninstalls require the app to be reopened)
//    so fetching it once is correct and avoids a ~100ms channel
//    round-trip on every screen that needs the list.
//    Call invalidateAppCache() if you ever need a fresh fetch.
//
//  Public surface:
//    hasUsagePermission()      — AppOpsManager check
//    openUsageSettings()       — opens ACTION_USAGE_ACCESS_SETTINGS
//    getStatsForRange()        — foreground-only minutes per package
//    getAppLabel()             — real system display name
//    getAppIcon()              — PNG bytes (handles AdaptiveIconDrawable)
//    getAllInstalledApps()     — CATEGORY_LAUNCHER filtered list, cached
//    invalidateAppCache()      — clears the in-memory app list cache
//    getForegroundApp()        — package name in foreground right now
// ─────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

// ─────────────────────────────────────────────────────────────
//  AppInfo — value object for one installed app
// ─────────────────────────────────────────────────────────────

class AppInfo {
  final String packageName;
  final String label;

  const AppInfo({required this.packageName, required this.label});

  @override
  String toString() => 'AppInfo($packageName, "$label")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppInfo && other.packageName == packageName;

  @override
  int get hashCode => packageName.hashCode;
}

// ─────────────────────────────────────────────────────────────
//  UsageChannel
// ─────────────────────────────────────────────────────────────

class UsageChannel {
  UsageChannel._();

  static const String _tag = 'UsageChannel';
  static const MethodChannel _ch = MethodChannel(AppConstants.usageChannel);

  // In-memory cache — populated on first call to getAllInstalledApps().
  // null = not yet fetched; non-null = already fetched (may be empty).
  static List<AppInfo>? _appCache;

  // ── Permission ────────────────────────────────────────────

  /// Returns true if the user has granted Usage Access to PhaseOut.
  static Future<bool> hasUsagePermission() async {
    try {
      return await _ch.invokeMethod<bool>('hasUsagePermission') ?? false;
    } catch (e) {
      AppLogger.e(_tag, 'hasUsagePermission error', e);
      return false;
    }
  }

  /// Opens the system Usage Access settings screen.
  static Future<void> openUsageSettings() async {
    try {
      await _ch.invokeMethod<void>('openUsageSettings');
    } catch (e) {
      AppLogger.e(_tag, 'openUsageSettings error', e);
    }
  }

  // ── Usage stats ───────────────────────────────────────────

  /// Returns foreground-only minutes per package for [startMs]→[endMs].
  static Future<Map<String, int>> getStatsForRange(
      int startMs, int endMs) async {
    try {
      final raw = await _ch.invokeMethod<Map>(
          'getUsageStats', {'startMs': startMs, 'endMs': endMs});
      if (raw == null) return const {};
      return Map<String, int>.fromEntries(
        raw.entries.map(
            (e) => MapEntry(e.key.toString(), (e.value as num).toInt())),
      );
    } catch (e) {
      AppLogger.e(_tag, 'getStatsForRange error', e);
      return const {};
    }
  }

  // ── App metadata ──────────────────────────────────────────

  /// Returns the human-readable display label for [packageName].
  /// Checks the in-memory cache before making a channel call.
  static Future<String> getAppLabel(String packageName) async {
    final cached = _appCache
        ?.where((a) => a.packageName == packageName)
        .firstOrNull;
    if (cached != null) return cached.label;

    try {
      return await _ch.invokeMethod<String>(
              'getAppLabel', {'packageName': packageName}) ??
          packageName;
    } catch (e) {
      AppLogger.e(_tag, 'getAppLabel($packageName) error', e);
      return packageName;
    }
  }

  /// Returns the app icon for [packageName] as raw PNG bytes.
  /// Returns null if the package is not found or icon cannot be decoded.
  static Future<Uint8List?> getAppIcon(String packageName) async {
    try {
      final raw = await _ch.invokeMethod<List<int>>(
          'getAppIcon', {'packageName': packageName});
      if (raw == null) return null;
      return Uint8List.fromList(raw);
    } catch (e) {
      AppLogger.e(_tag, 'getAppIcon($packageName) error', e);
      return null;
    }
  }

  // ── App list (cached) ─────────────────────────────────────

  /// Returns every app that has a launcher icon on this device.
  ///
  /// The Kotlin side uses queryIntentActivities(ACTION_MAIN +
  /// CATEGORY_LAUNCHER) — the same query the system app drawer uses.
  /// Reliable across all OEMs; does not depend on whether the app
  /// has ever been opened.
  ///
  /// Result is cached for the process lifetime. Safe because the
  /// installed-app set does not change while the app is running.
  static Future<List<AppInfo>> getAllInstalledApps() async {
    if (_appCache != null) {
      AppLogger.d(_tag,
          'getAllInstalledApps: ${_appCache!.length} apps from cache');
      return _appCache!;
    }

    try {
      final raw = await _ch.invokeMethod<List>('getAllInstalledApps');
      if (raw == null) {
        _appCache = const [];
        return const [];
      }

      _appCache = raw
          .whereType<Map>()
          .map((m) => AppInfo(
                packageName: m['packageName']?.toString() ?? '',
                label:       m['label']?.toString() ?? '',
              ))
          .where((a) => a.packageName.isNotEmpty && a.label.isNotEmpty)
          .toList(growable: false);

      AppLogger.i(_tag,
          'getAllInstalledApps: fetched ${_appCache!.length} apps');
      return _appCache!;
    } catch (e) {
      AppLogger.e(_tag, 'getAllInstalledApps error', e);
      _appCache = const [];
      return const [];
    }
  }

  /// Clears the in-memory app list cache.
  static void invalidateAppCache() {
    _appCache = null;
    AppLogger.d(_tag, 'App list cache invalidated');
  }

  // ── Foreground detection ──────────────────────────────────

  /// Returns the package currently in the foreground (2-second window).
  /// Returns null if permission is not granted or detection fails.
  static Future<String?> getForegroundApp() async {
    try {
      return await _ch.invokeMethod<String>('getForegroundApp');
    } catch (e) {
      AppLogger.e(_tag, 'getForegroundApp error', e);
      return null;
    }
  }
}