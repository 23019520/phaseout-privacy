// ─────────────────────────────────────────────────────────────
//  lib/services/focus_service.dart
//  PhaseOut — Focus session (Dart UI layer)
//
//  PhaseOutService (Kotlin) handles foreground detection and
//  block notifications autonomously. This class manages UI
//  state, DB writes, and delegates control to BgsBridge.
// ─────────────────────────────────────────────────────────────

import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../db/database_helper.dart';
import '../models/focus_session_model.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'bgs_bridge.dart';

class FocusService {

  static const String _tag = 'FocusService';
  FocusService._();

  static const String _keyActive    = 'focus_session_active';
  static const String _keyAllowlist = 'focus_session_allowlist';
  static const String _keySessionId = 'focus_session_id';

  // ── Start a focus session ─────────────────────────────────
  static Future<void> startSession(List<String> allowlist) async {
    final fullAllowlist = [AppConstants.packageName, ...allowlist];

    // Write session to DB
    final session = FocusSessionModel(
      startTime: DateTime.now(),
      allowlist: fullAllowlist,
    );
    final id = await DatabaseHelper.instance.insertFocusSession(session);

    // Persist state for UI
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyActive, true);
    await prefs.setString(_keyAllowlist, jsonEncode(fullAllowlist));
    await prefs.setInt(_keySessionId, id);

    // Tell PhaseOutService to start monitoring
    await BgsBridge.startFocus(fullAllowlist);

    AppLogger.i(_tag,
        'Focus session started. ID: $id, '
        'Allowlist: ${fullAllowlist.length} apps');
  }

  // ── Stop the active focus session ─────────────────────────
  static Future<void> stopSession() async {
    final prefs     = await SharedPreferences.getInstance();
    final sessionId = prefs.getInt(_keySessionId);

    if (sessionId != null) {
      await DatabaseHelper.instance.endFocusSession(sessionId);
    }

    await prefs.setBool(_keyActive, false);
    await prefs.remove(_keyAllowlist);
    await prefs.remove(_keySessionId);

    // Tell PhaseOutService to stop monitoring
    await BgsBridge.stopFocus();

    AppLogger.i(_tag, 'Focus session stopped');
  }

  // ── UI state queries ──────────────────────────────────────

  static Future<bool> isSessionActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyActive) ?? false;
  }

  static Future<List<String>> getAllowlist() async {
    final prefs         = await SharedPreferences.getInstance();
    final allowlistJson = prefs.getString(_keyAllowlist);
    if (allowlistJson == null) return [];
    return List<String>.from(jsonDecode(allowlistJson) as List);
  }
}