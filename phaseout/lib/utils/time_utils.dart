// ─────────────────────────────────────────────────────────────
//  lib/utils/time_utils.dart
//  PhaseOut — Time and date utility functions
//
//  Pure functions only — no state, no dependencies on services.
//  These are unit-testable in isolation.
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../models/schedule_model.dart';
import 'constants.dart';

class TimeUtils {

  TimeUtils._();

  // ── Core scheduler check ───────────────────────────────────
  // Returns true if the current moment matches this schedule.
  // Called by SchedulerService on every 60-second tick.
  //
  // Match conditions:
  //   1. Current HH:mm == schedule triggerTime HH:mm
  //   2. Today's weekday is in schedule.daysOfWeek
  static bool isMatchNow(ScheduleModel schedule) {
    final now     = DateTime.now();
    final nowTOD  = TimeOfDay.fromDateTime(now);

    final timeMatch = nowTOD.hour   == schedule.triggerTime.hour &&
                      nowTOD.minute == schedule.triggerTime.minute;

    // DateTime.weekday: 1=Monday … 7=Sunday
    final dayMatch  = schedule.daysOfWeek.contains(now.weekday);

    return timeMatch && dayMatch;
  }

  // ── Next occurrence ────────────────────────────────────────
  // Returns the next DateTime this schedule will fire.
  // Used by the ScheduleCard to show "Next: Tonight at 11:00 PM".
  static DateTime nextOccurrence(ScheduleModel schedule) {
    final now = DateTime.now();

    // Build today's candidate DateTime at the trigger time
    DateTime candidate = DateTime(
      now.year,
      now.month,
      now.day,
      schedule.triggerTime.hour,
      schedule.triggerTime.minute,
    );

    // If today's time has already passed, start looking from tomorrow
    if (candidate.isBefore(now) || candidate.isAtSameMomentAs(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }

    // Walk forward day-by-day until we land on a matching weekday
    // Cap at 8 iterations (one full week + 1) to prevent infinite loop
    for (int i = 0; i < 8; i++) {
      if (schedule.daysOfWeek.contains(candidate.weekday)) {
        return candidate;
      }
      candidate = candidate.add(const Duration(days: 1));
    }

    // Fallback (should never reach here for a valid schedule)
    return candidate;
  }

  // ── Human-readable relative time ──────────────────────────
  // Converts a future DateTime to a display string.
  // e.g. "Tonight", "Tomorrow", "Monday", "In 3 days"
  static String relativeOccurrence(DateTime target) {
  final now   = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day   = DateTime(target.year, target.month, target.day);
  final diff  = day.difference(today).inDays;

  if (diff == 0) {
    return target.hour < 12 ? 'This morning' : 'Tonight';
  }
  if (diff == 1) return 'Tomorrow';
  if (diff < 7)  return AppConstants.dayAbbreviations[target.weekday - 1];
  return 'In $diff days';
}

  // ── TimeOfDay formatters ───────────────────────────────────

  // "11:00 PM"
  static String formatTimeOfDay(TimeOfDay time) {
    final hour   = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  // "23:00" — 24-hour for display in compact contexts
  static String formatTimeOfDay24(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ── Weekday helpers ────────────────────────────────────────

  // "Mon" from Dart weekday int 1
  static String dayName(int weekday) {
    assert(weekday >= 1 && weekday <= 7, 'weekday must be 1–7');
    return AppConstants.dayAbbreviations[weekday - 1];
  }

  // "M" from Dart weekday int 1
  static String dayLetter(int weekday) {
    assert(weekday >= 1 && weekday <= 7, 'weekday must be 1–7');
    return AppConstants.dayLetters[weekday - 1];
  }

  // Converts a list of weekday ints to a readable summary
  // e.g. [1,2,3,4,5] → "Weekdays"
  //      [6,7]       → "Weekends"
  //      [1,2,3,4,5,6,7] → "Every day"
  //      [1,3,5]     → "Mon, Wed, Fri"
  static String formatDayList(List<int> days) {
    if (days.isEmpty) return 'No days selected';
    final sorted = List<int>.from(days)..sort();
if (sorted.length == 7)                          { return 'Every day'; }
if (sorted.toSet().containsAll({1,2,3,4,5}) &&
    !sorted.contains(6) && !sorted.contains(7)) { return 'Weekdays'; }
if (sorted.contains(6) && sorted.contains(7) &&
    sorted.length == 2)                          { return 'Weekends'; }
    return sorted.map(dayName).join(', ');
  }
}
