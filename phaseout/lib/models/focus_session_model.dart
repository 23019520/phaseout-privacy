// ─────────────────────────────────────────────────────────────
//  lib/models/focus_session_model.dart
//  PhaseOut — Focus session data model
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

class FocusSessionModel {

  final int?         id;
  final DateTime     startTime;
  final DateTime?    endTime;        // null while session is active
  final List<String> blockedApps;   // package names blocked during session
  final int          blockedAttempts;

  const FocusSessionModel({
    this.id,
    required this.startTime,
    this.endTime,
    required this.blockedApps,
    this.blockedAttempts = 0,
  });

  factory FocusSessionModel.fromMap(Map<String, dynamic> map) {
    return FocusSessionModel(
      id:              map['id'] as int?,
      startTime:       DateTime.parse(map['start_time'] as String),
      endTime:         map['end_time'] != null
                           ? DateTime.parse(map['end_time'] as String)
                           : null,
      blockedApps:     List<String>.from(
                           jsonDecode(map['blockedApps'] as String) as List),
      blockedAttempts: map['blocked_attempts'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'start_time':       startTime.toIso8601String(),
      'end_time':         endTime?.toIso8601String(),
      'blockedApps':      jsonEncode(blockedApps),
      'blocked_attempts': blockedAttempts,
    };
  }

  FocusSessionModel copyWith({
    int?           id,
    DateTime?      startTime,
    DateTime?      endTime,
    List<String>?  blockedApps,
    int?           blockedAttempts,
  }) {
    return FocusSessionModel(
      id:              id              ?? this.id,
      startTime:       startTime       ?? this.startTime,
      endTime:         endTime         ?? this.endTime,
      blockedApps:     blockedApps     ?? this.blockedApps,
      blockedAttempts: blockedAttempts ?? this.blockedAttempts,
    );
  }

  bool get isActive => endTime == null;

  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  String get formattedDuration {
    final d = duration;
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  bool isBlocked(String packageName) => blockedApps.contains(packageName);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FocusSessionModel && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'FocusSessionModel(id: $id, active: $isActive, '
      'blockedApps: ${blockedApps.length} apps, blocked: $blockedAttempts)';
}