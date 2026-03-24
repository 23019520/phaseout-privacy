// ─────────────────────────────────────────────────────────────
//  lib/models/schedule_model.dart
//  PhaseOut — Schedule data model
//
//  Represents one user-created recurring timed action.
//  Maps 1:1 to a row in the `schedules` sqflite table.
//
//  Example: "Stop media every weeknight at 23:00"
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class ScheduleModel {

  final int?     id;           // null before first DB insert
  final String   name;         // user-facing label e.g. "Bedtime"
  final TimeOfDay triggerTime; // when it fires e.g. 23:00
  final List<int> daysOfWeek;  // Dart weekdays: 1=Mon … 7=Sun
  final List<String> actions;  // e.g. ['stop_media', 'send_notification']
  final bool     enabled;
  final DateTime createdAt;

  const ScheduleModel({
    this.id,
    required this.name,
    required this.triggerTime,
    required this.daysOfWeek,
    required this.actions,
    this.enabled = true,
    required this.createdAt,
  });

  // ── Deserialise from sqflite row ───────────────────────────
  factory ScheduleModel.fromMap(Map<String, dynamic> map) {
    final timeParts = (map['trigger_time'] as String).split(':');
    return ScheduleModel(
      id:          map['id'] as int?,
      name:        map['name'] as String,
      triggerTime: TimeOfDay(
        hour:   int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      ),
      daysOfWeek: List<int>.from(
        jsonDecode(map['days_of_week'] as String) as List,
      ),
      actions: List<String>.from(
        jsonDecode(map['actions_json'] as String) as List,
      ),
      enabled:   (map['enabled'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  // ── Serialise to sqflite row ───────────────────────────────
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name':        name,
      'trigger_time': '${triggerTime.hour.toString().padLeft(2, '0')}:'
                      '${triggerTime.minute.toString().padLeft(2, '0')}',
      'days_of_week': jsonEncode(daysOfWeek),
      'actions_json': jsonEncode(actions),
      'enabled':     enabled ? 1 : 0,
      'created_at':  createdAt.toIso8601String(),
    };
  }

  // ── Immutable update helper ────────────────────────────────
  // Returns a new ScheduleModel with only the specified fields replaced.
  // Used when toggling enabled state without rewriting the whole object.
  ScheduleModel copyWith({
    int?          id,
    String?       name,
    TimeOfDay?    triggerTime,
    List<int>?    daysOfWeek,
    List<String>? actions,
    bool?         enabled,
    DateTime?     createdAt,
  }) {
    return ScheduleModel(
      id:          id          ?? this.id,
      name:        name        ?? this.name,
      triggerTime: triggerTime ?? this.triggerTime,
      daysOfWeek:  daysOfWeek  ?? this.daysOfWeek,
      actions:     actions     ?? this.actions,
      enabled:     enabled     ?? this.enabled,
      createdAt:   createdAt   ?? this.createdAt,
    );
  }

  // ── Convenience getters ────────────────────────────────────

  // Human-readable time string e.g. "11:00 PM"
  String get formattedTime {
    final hour   = triggerTime.hourOfPeriod == 0 ? 12 : triggerTime.hourOfPeriod;
    final minute = triggerTime.minute.toString().padLeft(2, '0');
    final period = triggerTime.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  // Abbreviated day names for display e.g. "Mon, Tue, Wed"
  String get formattedDays {
    return daysOfWeek
        .map((d) => AppConstants.dayAbbreviations[d - 1])
        .join(', ');
  }

  // True if this schedule fires every day
  bool get isDaily => daysOfWeek.length == 7;

  // True if this schedule fires on weekdays only
  bool get isWeekdays =>
      daysOfWeek.toSet().containsAll({1, 2, 3, 4, 5}) &&
      !daysOfWeek.contains(6) &&
      !daysOfWeek.contains(7);

  // ── Equality ───────────────────────────────────────────────
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduleModel && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ScheduleModel(id: $id, name: $name, time: $formattedTime, '
      'days: $formattedDays, enabled: $enabled)';
}
