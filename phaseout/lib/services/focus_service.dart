// ─────────────────────────────────────────────────────────────
//  lib/services/focus_service.dart
//  PhaseOut — Focus session coordinator (Dart / UI layer)
//
//  Responsibilities:
//    1. Write focus sessions to SQLite (start, end, blocked count).
//    2. Persist active-session state in SharedPreferences so the
//       UI can restore correctly after a hot restart.
//    3. Delegate foreground detection and block notifications to
//       PhaseOutService (Kotlin) via BgsBridge.
//
//  Public surface:
//    startSession(blockedApps)  — starts session, tells Kotlin service
//    stopSession()              — ends session, tells Kotlin service
//    isSessionActive()          — UI state query
//    getBlockedApps()           — retrieve current session blocked list
//    incrementBlockedCount()    — called by Kotlin via MethodChannel
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../models/focus_session_model.dart';
import '../utils/logger.dart';
import 'bgs_bridge.dart';

class FocusService {
  FocusService._();

  static const String _tag = 'FocusService';

  // SharedPreferences keys
  static const String _kActive      = 'focus.active';
  static const String _kBlockedApps = 'focus.blocked_apps';
  static const String _kSessionId   = 'focus.session_id';

  // ── Start ──────────────────────────────────────────────────

  /// Starts a focus session blocking [blockedApps] packages.
  /// PhaseOut's own package is never added here — the blacklist
  /// model doesn't need it (everything not in the list is allowed).
  ///
  /// Throws if a session is already active — callers should check
  /// [isSessionActive] before calling this.
  static Future<void> startSession(List<String> blockedApps) async {
    final alreadyActive = await isSessionActive();
    if (alreadyActive) {
      AppLogger.w(_tag, 'startSession called while session already active');
      return;
    }

    // 1 — Persist to DB.
    final session = FocusSessionModel(
      startTime:   DateTime.now(),
      blockedApps: blockedApps,
    );
    final id = await DatabaseHelper.instance.insertFocusSession(session);

    // 2 — Persist UI state.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kActive, true);
    await prefs.setString(_kBlockedApps, jsonEncode(blockedApps));
    await prefs.setInt(_kSessionId, id);

    // 3 — Tell PhaseOutService to start monitoring.
    await BgsBridge.startFocus(blockedApps);

    AppLogger.i(_tag,
        'Focus session started — id: $id, '
        'blockedApps: ${blockedApps.length} apps');
  }

  // ── Stop ───────────────────────────────────────────────────

  static Future<void> stopSession() async {
    final prefs     = await SharedPreferences.getInstance();
    final sessionId = prefs.getInt(_kSessionId);

    if (sessionId != null) {
      await DatabaseHelper.instance.endFocusSession(sessionId);
      AppLogger.i(_tag, 'Focus session ended — id: $sessionId');
    }

    await prefs.setBool(_kActive, false);
    await prefs.remove(_kBlockedApps);
    await prefs.remove(_kSessionId);

    await BgsBridge.stopFocus();
  }

  // ── State queries ─────────────────────────────────────────

  static Future<bool> isSessionActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kActive) ?? false;
  }

  /// Returns the blocked-apps list for the active session.
  /// Returns an empty list when no session is active.
  static Future<List<String>> getBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_kBlockedApps);
    if (raw == null) return const [];
    return List<String>.from(jsonDecode(raw) as List);
  }

  static Future<int?> activeSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kSessionId);
  }

  // ── Block count ───────────────────────────────────────────

  static Future<void> incrementBlockedCount() async {
    final id = await activeSessionId();
    if (id == null) return;
    await DatabaseHelper.instance.incrementBlockedAttempts(id);
    AppLogger.d(_tag, 'Blocked attempt recorded for session $id');
  }
}