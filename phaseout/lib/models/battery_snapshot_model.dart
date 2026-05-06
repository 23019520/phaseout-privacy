// ─────────────────────────────────────────────────────────────
//  lib/models/battery_snapshot_model.dart  (UPGRADED — v5)
//  PhaseOut — Battery snapshot data model
//
//  Maps 1:1 to a row in the battery_snapshots sqflite table.
//  Written every 5 minutes by BatteryPredictionService.
//
//  v5 adds: screen_on_seconds (nullable INTEGER)
//  This feeds the DayProfileEngine so it can correlate
//  screen activity with drain rate on each day-of-week.
// ─────────────────────────────────────────────────────────────

class BatterySnapshotModel {

  final int?     id;
  final DateTime recordedAt;
  final int      level;             // 0–100
  final bool     charging;
  final int      dayOfWeek;         // DateTime.weekday: 1=Mon…7=Sun

  /// Screen-on seconds since the last snapshot tick.
  /// Null for rows recorded before v5 (backward compatible).
  final int?     screenOnSeconds;

  const BatterySnapshotModel({
    this.id,
    required this.recordedAt,
    required this.level,
    required this.charging,
    required this.dayOfWeek,
    this.screenOnSeconds,
  });

  // ── Deserialise from sqflite row ───────────────────────────
  factory BatterySnapshotModel.fromMap(Map<String, dynamic> map) {
    return BatterySnapshotModel(
      id:              map['id']              as int?,
      recordedAt:      DateTime.parse(map['recorded_at'] as String),
      level:           map['level']           as int,
      charging:        (map['charging']       as int) == 1,
      dayOfWeek:       map['day_of_week']     as int,
      screenOnSeconds: map['screen_on_seconds'] as int?,
    );
  }

  // ── Serialise to sqflite row ───────────────────────────────
  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'recorded_at':       recordedAt.toIso8601String(),
    'level':             level,
    'charging':          charging ? 1 : 0,
    'day_of_week':       dayOfWeek,
    'screen_on_seconds': screenOnSeconds,
  };

  // ── Convenience getters ────────────────────────────────────

  bool get isLow      => level < 20;
  bool get isCritical => level < 10;
  bool get isHealthy  => level >= 50;

  String get formattedLevel => '$level%';

  /// Screen-on minutes derived from screenOnSeconds.
  double get screenOnMinutes => (screenOnSeconds ?? 0) / 60.0;

  static const _dayNames = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

  String get dayName => _dayNames[(dayOfWeek - 1).clamp(0, 6)];

  // ── Equality ───────────────────────────────────────────────
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatterySnapshotModel && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'BatterySnapshotModel(level: $level%, charging: $charging, '
      'day: $dayName, screenOn: ${screenOnMinutes.toStringAsFixed(1)}m, '
      'at: $recordedAt)';
}
