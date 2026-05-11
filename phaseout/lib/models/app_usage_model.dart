// ─────────────────────────────────────────────────────────────
//  lib/models/app_usage_model.dart
//  PhaseOut — Per-app daily usage model
//
//  FIX: copyWith now supports explicit null for limitMinutes
//       via clearLimit flag (unchanged), but toMap() now omits
//       limit_minutes entirely when null so SQLite stores NULL
//       rather than the integer 0.  setAppLimit(pkg, 0) in the
//       DB layer must translate 0 → null before persisting.
// ─────────────────────────────────────────────────────────────

class AppUsageModel {
  final int?    id;
  final String  packageName;
  final String  appLabel;
  final String  date;
  final int     usageMinutes;
  final int?    limitMinutes;   // null = no limit

  const AppUsageModel({
    this.id,
    required this.packageName,
    required this.appLabel,
    required this.date,
    required this.usageMinutes,
    this.limitMinutes,
  });

  // ── Persistence ────────────────────────────────────────────

  factory AppUsageModel.fromMap(Map<String, dynamic> map) => AppUsageModel(
        id:           map['id']            as int?,
        packageName:  map['package_name']  as String,
        appLabel:     (map['app_label']    as String?) ?? '',
        date:         map['date']          as String,
        usageMinutes: map['usage_minutes'] as int,
        limitMinutes: map['limit_minutes'] as int?,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'package_name':  packageName,
        'app_label':     appLabel,
        'date':          date,
        'usage_minutes': usageMinutes,
        // Store NULL when no limit — never store 0 as a limit value.
        // Storing 0 would make isOverLimit true for any non-zero usage.
        if (limitMinutes != null) 'limit_minutes': limitMinutes,
      };

  // ── Immutable update ───────────────────────────────────────

  AppUsageModel copyWith({
    int?    id,
    String? packageName,
    String? appLabel,
    String? date,
    int?    usageMinutes,
    int?    limitMinutes,
    bool    clearLimit = false,
  }) => AppUsageModel(
        id:           id           ?? this.id,
        packageName:  packageName  ?? this.packageName,
        appLabel:     appLabel     ?? this.appLabel,
        date:         date         ?? this.date,
        usageMinutes: usageMinutes ?? this.usageMinutes,
        limitMinutes: clearLimit   ? null : (limitMinutes ?? this.limitMinutes),
      );

  // ── Limit state ────────────────────────────────────────────

  bool get isOverLimit =>
      limitMinutes != null && limitMinutes! > 0 && usageMinutes >= limitMinutes!;

  int? get minutesRemaining =>
      (limitMinutes != null && limitMinutes! > 0)
          ? limitMinutes! - usageMinutes
          : null;

  double? get usageProgress =>
      (limitMinutes != null && limitMinutes! > 0)
          ? (usageMinutes / limitMinutes!).clamp(0.0, 1.0)
          : null;

  // ── Formatting helpers ─────────────────────────────────────

  String get formattedUsage => formatMinutes(usageMinutes);

  String get formattedLimit =>
      (limitMinutes != null && limitMinutes! > 0)
          ? formatMinutes(limitMinutes!)
          : 'No limit';

  static String formatMinutes(int m) {
    if (m <= 0) return '0m';
    if (m < 60) return '${m}m';
    final h   = m ~/ 60;
    final rem = m % 60;
    return rem == 0 ? '${h}h' : '${h}h ${rem}m';
  }

  // ── Date helpers ───────────────────────────────────────────

  static String todayString() => _formatDate(DateTime.now());

  static String formatDate(DateTime date) => _formatDate(date);

  static String _formatDate(DateTime d) =>
      '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ── Equality ───────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppUsageModel &&
          other.packageName == packageName &&
          other.date == date;

  @override
  int get hashCode => Object.hash(packageName, date);

  @override
  String toString() =>
      'AppUsageModel($packageName, $date, '
      'usage: $formattedUsage, limit: $formattedLimit)';
}