// ─────────────────────────────────────────────────────────────
//  lib/models/usage_event_model.dart
//  PhaseOut — Usage event / audit log model
//
//  Every time the background service fires an action, a
//  UsageEventModel is written to the usage_events table.
//  This is both a debug audit trail and the ML training data
//  source for Sprint 4 (routine suggestions).
//
//  Example: schedule "Bedtime" fired at 23:00, action
//  stop_media executed, outcome: success.
// ─────────────────────────────────────────────────────────────

import '../utils/constants.dart';

class UsageEventModel {

  final int?     id;
  final DateTime eventTime;
  final String   eventType;    // AppConstants.eventActionFired etc.
  final int?     referenceId;  // FK to schedules.id or scenarios.id
  final String?  outcome;      // AppConstants.outcomeSuccess etc.
  final String?  detail;       // optional extra info e.g. action type

  const UsageEventModel({
    this.id,
    required this.eventTime,
    required this.eventType,
    this.referenceId,
    this.outcome,
    this.detail,
  });

  // ── Deserialise from sqflite row ───────────────────────────
  factory UsageEventModel.fromMap(Map<String, dynamic> map) {
    return UsageEventModel(
      id:          map['id'] as int?,
      eventTime:   DateTime.parse(map['event_time'] as String),
      eventType:   map['event_type'] as String,
      referenceId: map['reference_id'] as int?,
      outcome:     map['outcome'] as String?,
      detail:      map['detail'] as String?,
    );
  }

  // ── Serialise to sqflite row ───────────────────────────────
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'event_time':   eventTime.toIso8601String(),
      'event_type':   eventType,
      'reference_id': referenceId,
      'outcome':      outcome,
      'detail':       detail,
    };
  }

  // ── Named constructors for common event types ──────────────
  // Saves boilerplate at the call site in scheduler_service.dart

  factory UsageEventModel.actionFired({
    required int    scheduleId,
    required String action,
    required String outcome,
  }) {
    return UsageEventModel(
      eventTime:   DateTime.now(),
      eventType:   AppConstants.eventActionFired,
      referenceId: scheduleId,
      outcome:     outcome,
      detail:      action,
    );
  }

  factory UsageEventModel.suggestionShown({required String suggestionId}) {
    return UsageEventModel(
      eventTime: DateTime.now(),
      eventType: AppConstants.eventSuggestionShown,
      detail:    suggestionId,
    );
  }

  factory UsageEventModel.suggestionAccepted({required String suggestionId}) {
    return UsageEventModel(
      eventTime: DateTime.now(),
      eventType: AppConstants.eventSuggestionAccepted,
      detail:    suggestionId,
    );
  }

  // ── Equality ───────────────────────────────────────────────
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsageEventModel && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'UsageEventModel(id: $id, type: $eventType, '
      'ref: $referenceId, outcome: $outcome, detail: $detail)';
}
