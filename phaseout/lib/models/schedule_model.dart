// ─────────────────────────────────────────────────────────────
//  lib/models/schedule_model.dart
//  PhaseOut — Schedule data model
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class ScheduleModel {

  final int?        id;
  final String      name;
  final TimeOfDay   triggerTime;
  final List<int>   daysOfWeek;
  final List<String> actions;
  final bool        enabled;
  final DateTime    createdAt;

  // Morning alarm wake time — null if not set
  final TimeOfDay?  wakeTime;

  const ScheduleModel({
    this.id,
    required this.name,
    required this.triggerTime,
    required this.daysOfWeek,
    required this.actions,
    this.enabled  = true,
    required this.createdAt,
    this.wakeTime,
  });

  // ── Deserialise from sqflite row ───────────────────────────
  factory ScheduleModel.fromMap(Map<String, dynamic> map) {
    final timeParts = (map['trigger_time'] as String).split(':');

    // wakeTime — may not exist in older DB rows
    TimeOfDay? wakeTime;
    if (map['wake_hour'] != null && map['wake_minute'] != null) {
      wakeTime = TimeOfDay(
        hour:   map['wake_hour'] as int,
        minute: map['wake_minute'] as int,
      );
    }

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
      wakeTime:  wakeTime,
    );
  }

  // ── Serialise to sqflite row ───────────────────────────────
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name':         name,
      'trigger_time': '${triggerTime.hour.toString().padLeft(2, '0')}:'
                      '${triggerTime.minute.toString().padLeft(2, '0')}',
      'days_of_week': jsonEncode(daysOfWeek),
      'actions_json': jsonEncode(actions),
      'enabled':      enabled ? 1 : 0,
      'created_at':   createdAt.toIso8601String(),
      // wakeTime — only written if set
      if (wakeTime != null) 'wake_hour':   wakeTime!.hour,
      if (wakeTime != null) 'wake_minute': wakeTime!.minute,
    };
  }

  // ── Immutable update helper ────────────────────────────────
  ScheduleModel copyWith({
    int?           id,
    String?        name,
    TimeOfDay?     triggerTime,
    List<int>?     daysOfWeek,
    List<String>?  actions,
    bool?          enabled,
    DateTime?      createdAt,
    TimeOfDay?     wakeTime,
    bool           clearWakeTime = false,
  }) {
    return ScheduleModel(
      id:          id          ?? this.id,
      name:        name        ?? this.name,
      triggerTime: triggerTime ?? this.triggerTime,
      daysOfWeek:  daysOfWeek  ?? this.daysOfWeek,
      actions:     actions     ?? this.actions,
      enabled:     enabled     ?? this.enabled,
      createdAt:   createdAt   ?? this.createdAt,
      // clearWakeTime: pass true to explicitly remove the wake time
      wakeTime:    clearWakeTime ? null : (wakeTime ?? this.wakeTime),
    );
  }

  // ── Convenience getters ────────────────────────────────────

  String get formattedTime {
    final hour   = triggerTime.hourOfPeriod == 0 ? 12 : triggerTime.hourOfPeriod;
    final minute = triggerTime.minute.toString().padLeft(2, '0');
    final period = triggerTime.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String get formattedWakeTime {
    if (wakeTime == null) return '';
    final hour   = wakeTime!.hourOfPeriod == 0 ? 12 : wakeTime!.hourOfPeriod;
    final minute = wakeTime!.minute.toString().padLeft(2, '0');
    final period = wakeTime!.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String get formattedDays {
    return daysOfWeek
        .map((d) => AppConstants.dayAbbreviations[d - 1])
        .join(', ');
  }

  bool get isDaily    => daysOfWeek.length == 7;
  bool get isWeekdays =>
      daysOfWeek.toSet().containsAll({1, 2, 3, 4, 5}) &&
      !daysOfWeek.contains(6) &&
      !daysOfWeek.contains(7);

  bool get hasMorningAlarm => wakeTime != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduleModel && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ScheduleModel(id: $id, name: $name, time: $formattedTime, '
      'days: $formattedDays, enabled: $enabled, '
      'wakeTime: ${wakeTime != null ? formattedWakeTime : "none"})';
}