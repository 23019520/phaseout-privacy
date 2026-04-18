// ─────────────────────────────────────────────────────────────
//  lib/models/focus_session_model.dart
//  PhaseOut — Focus session data model
//
//  Represents one active or historical focus session.
//  Maps 1:1 to a row in the focus_sessions sqflite table.
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

class FocusSessionModel {

  final int?      id;
  final DateTime  startTime;
  final DateTime? endTime;       // null while session is active
  final List<String> allowlist;  // package names allowed during session
  final int       blockedAttempts;

  const FocusSessionModel({
    this.id,
    required this.startTime,
    this.endTime,
    required this.allowlist,
    this.blockedAttempts = 0,
  });

  // ── Deserialise from sqflite row ───────────────────────────
  factory FocusSessionModel.fromMap(Map<String, dynamic> map) {
    return FocusSessionModel(
      id:               map['id'] as int?,
      startTime:        DateTime.parse(map['start_time'] as String),
      endTime:          map['end_time'] != null
                            ? DateTime.parse(map['end_time'] as String)
                            : null,
      allowlist:        List<String>.from(
                            jsonDecode(map['allowlist'] as String) as List),
      blockedAttempts:  map['blocked_attempts'] as int,
    );
  }

  // ── Serialise to sqflite row ───────────────────────────────
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'start_time':       startTime.toIso8601String(),
      'end_time':         endTime?.toIso8601String(),
      'allowlist':        jsonEncode(allowlist),
      'blocked_attempts': blockedAttempts,
    };
  }

  // ── Immutable update helper ────────────────────────────────
  FocusSessionModel copyWith({
    int?           id,
    DateTime?      startTime,
    DateTime?      endTime,
    List<String>?  allowlist,
    int?           blockedAttempts,
  }) {
    return FocusSessionModel(
      id:              id              ?? this.id,
      startTime:       startTime       ?? this.startTime,
      endTime:         endTime         ?? this.endTime,
      allowlist:       allowlist       ?? this.allowlist,
      blockedAttempts: blockedAttempts ?? this.blockedAttempts,
    );
  }

  // ── Convenience getters ────────────────────────────────────

  bool get isActive => endTime == null;

  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  String get formattedDuration {
    final d = duration;
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) { return '${m}m'; }
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  bool isAllowed(String packageName) => allowlist.contains(packageName);

  // ── Equality ───────────────────────────────────────────────
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FocusSessionModel && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'FocusSessionModel(id: $id, active: $isActive, '
      'allowlist: ${allowlist.length} apps, blocked: $blockedAttempts)';
}