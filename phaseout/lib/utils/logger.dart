// ─────────────────────────────────────────────────────────────
//  lib/utils/logger.dart
//  PhaseOut — Centralised logging wrapper
//
//  In DEBUG mode   → prints full messages + stack traces to console
//  In RELEASE mode → errors only, forwarded to Firebase Crashlytics
//
//  Usage:
//    AppLogger.d('SchedulerService', 'Tick fired at 23:00');
//    AppLogger.e('BackgroundService', 'Failed to start', error, stackTrace);
// ─────────────────────────────────────────────────────────────

import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class AppLogger {

  AppLogger._(); // prevent instantiation

  // ── Debug ──────────────────────────────────────────────────
  // General info logs. Only printed in debug builds, silent in release.
  static void d(String tag, String message) {
    if (kDebugMode) {
      dev.log('[$tag] $message', name: 'PhaseOut.DEBUG');
    }
  }

  // ── Info ───────────────────────────────────────────────────
  // Important lifecycle events (service started, schedule fired, etc.)
  // Printed in debug. Silent in release.
  static void i(String tag, String message) {
    if (kDebugMode) {
      dev.log('[$tag] $message', name: 'PhaseOut.INFO');
    }
  }

  // ── Warning ────────────────────────────────────────────────
  // Something unexpected happened but the app can continue.
  // Printed in debug. Logged as a non-fatal in release.
  static void w(String tag, String message, [Object? error]) {
    if (kDebugMode) {
      dev.log('[$tag] WARNING: $message', name: 'PhaseOut.WARN', error: error);
    } else {
      FirebaseCrashlytics.instance.log('[$tag] WARNING: $message');
    }
  }

  // ── Error ──────────────────────────────────────────────────
  // Serious failures. Always printed in debug with full stack trace.
  // In release: recorded as a non-fatal event in Crashlytics.
  static void e(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (kDebugMode) {
      dev.log(
        '[$tag] ERROR: $message',
        name: 'PhaseOut.ERROR',
        error: error,
        stackTrace: stackTrace,
      );
    } else {
      FirebaseCrashlytics.instance.recordError(
        error ?? message,
        stackTrace,
        reason: '[$tag] $message',
        fatal: false,
      );
    }
  }

  // ── Fatal ──────────────────────────────────────────────────
  // Unrecoverable errors that will crash the app.
  // Recorded as FATAL in Crashlytics regardless of build mode.
  static void fatal(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (kDebugMode) {
      dev.log(
        '[$tag] FATAL: $message',
        name: 'PhaseOut.FATAL',
        error: error,
        stackTrace: stackTrace,
      );
    }
    FirebaseCrashlytics.instance.recordError(
      error ?? message,
      stackTrace,
      reason: '[$tag] $message',
      fatal: true,
    );
  }

  // ── BGS helper ─────────────────────────────────────────────
  // The background service runs in a separate isolate and cannot
  // use dev.log directly in all Flutter versions. Use this variant
  // from inside background_service.dart and scheduler_service.dart.
  static void bg(String tag, String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[BGS][$tag] $message');
    }
  }
}
