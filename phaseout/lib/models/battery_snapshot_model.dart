// ─────────────────────────────────────────────────────────────
//  lib/models/battery_snapshot_model.dart
//  PhaseOut — Battery snapshot data model
//
//  Maps 1:1 to a row in the battery_snapshots sqflite table.
//  Written every 5 minutes by BatteryService.
//  Used by MLEngine in Sprint 4 for DAW charge predictions.
// ─────────────────────────────────────────────────────────────

class BatterySnapshotModel {

  final int?     id;
  final DateTime recordedAt;
  final int      level;       // 0–100
  final bool     charging;
  final int      dayOfWeek;   // DateTime.weekday: 1=Mon … 7=Sun

  const BatterySnapshotModel({
    this.id,
    required this.recordedAt,
    required this.level,
    required this.charging,
    required this.dayOfWeek,
  });

  // ── Deserialise from sqflite row ───────────────────────────
  factory BatterySnapshotModel.fromMap(Map<String, dynamic> map) {
    return BatterySnapshotModel(
      id:         map['id'] as int?,
      recordedAt: DateTime.parse(map['recorded_at'] as String),
      level:      map['level'] as int,
      charging:   (map['charging'] as int) == 1,
      dayOfWeek:  map['day_of_week'] as int,
    );
  }

  // ── Serialise to sqflite row ───────────────────────────────
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'recorded_at': recordedAt.toIso8601String(),
      'level':       level,
      'charging':    charging ? 1 : 0,
      'day_of_week': dayOfWeek,
    };
  }

  // ── Convenience getters ────────────────────────────────────

  bool get isLow      => level < 20;
  bool get isCritical => level < 10;
  bool get isHealthy  => level >= 50;

  String get formattedLevel => '$level%';

  String get dayName {
    const names = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return names[dayOfWeek - 1];
  }

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
      'day: $dayName, at: $recordedAt)';
}