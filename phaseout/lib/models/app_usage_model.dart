// ─────────────────────────────────────────────────────────────
//  lib/models/app_usage_model.dart
//  PhaseOut — Per-app daily usage model
//
//  Maps 1:1 to a row in the app_usage_daily sqflite table.
//  Keyed by (package_name, date) — one row per app per day.
//
//  Example: TikTok used for 87 minutes today, limit 60 minutes.
// ─────────────────────────────────────────────────────────────

//import '../utils/constants.dart';

class AppUsageModel {

  final int?    id;
  final String  packageName;   // e.g. com.zhiliaoapp.musically
  final String  appLabel;      // e.g. TikTok
  final String  date;          // YYYY-MM-DD
  final int     usageMinutes;  // total foreground minutes today
  final int?    limitMinutes;  // null = no limit set

  const AppUsageModel({
    this.id,
    required this.packageName,
    required this.appLabel,
    required this.date,
    required this.usageMinutes,
    this.limitMinutes,
  });

  // ── Deserialise from sqflite row ───────────────────────────
  factory AppUsageModel.fromMap(Map<String, dynamic> map) {
    return AppUsageModel(
      id:           map['id'] as int?,
      packageName:  map['package_name'] as String,
      appLabel:     map['app_label'] as String,
      date:         map['date'] as String,
      usageMinutes: map['usage_minutes'] as int,
      limitMinutes: map['limit_minutes'] as int?,
    );
  }

  // ── Serialise to sqflite row ───────────────────────────────
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'package_name':  packageName,
      'app_label':     appLabel,
      'date':          date,
      'usage_minutes': usageMinutes,
      'limit_minutes': limitMinutes,
    };
  }

  // ── Immutable update helper ────────────────────────────────
  AppUsageModel copyWith({
    int?    id,
    String? packageName,
    String? appLabel,
    String? date,
    int?    usageMinutes,
    int?    limitMinutes,
  }) {
    return AppUsageModel(
      id:           id           ?? this.id,
      packageName:  packageName  ?? this.packageName,
      appLabel:     appLabel     ?? this.appLabel,
      date:         date         ?? this.date,
      usageMinutes: usageMinutes ?? this.usageMinutes,
      limitMinutes: limitMinutes ?? this.limitMinutes,
    );
  }

  // ── Convenience getters ────────────────────────────────────

  // True if a limit is set and usage has reached or exceeded it
  bool get isOverLimit =>
      limitMinutes != null && usageMinutes >= limitMinutes!;

  // Minutes remaining before limit is hit. Null if no limit set.
  int? get minutesRemaining =>
      limitMinutes != null ? (limitMinutes! - usageMinutes) : null;

  // Usage as a 0.0–1.0 progress value. Null if no limit set.
  double? get usageProgress =>
      limitMinutes != null && limitMinutes! > 0
          ? (usageMinutes / limitMinutes!).clamp(0.0, 1.0)
          : null;

  // Human-readable usage string e.g. "1h 27m"
  String get formattedUsage {
    if (usageMinutes < 60) { return '${usageMinutes}m'; }
    final h = usageMinutes ~/ 60;
    final m = usageMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  // Human-readable limit string e.g. "2h" or "No limit"
  String get formattedLimit {
    if (limitMinutes == null) { return 'No limit'; }
    if (limitMinutes! < 60)   { return '${limitMinutes}m'; }
    final h = limitMinutes! ~/ 60;
    final m = limitMinutes! % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  // Today's date string in YYYY-MM-DD format
  static String todayString() {
    final now = DateTime.now();
    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  // ── Equality ───────────────────────────────────────────────
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUsageModel &&
          other.packageName == packageName &&
          other.date == date;

  @override
  int get hashCode => packageName.hashCode ^ date.hashCode;

  @override
  String toString() =>
      'AppUsageModel(pkg: $packageName, date: $date, '
      'usage: $formattedUsage, limit: $formattedLimit)';
}