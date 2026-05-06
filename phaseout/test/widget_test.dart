// test/widget_test.dart
// PhaseOut — Basic smoke tests
// These verify core models and utilities work correctly.
// UI widget tests are skipped because PhaseOut requires
// Android platform channels that are not available in the
// test environment.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phaseout/models/schedule_model.dart';
import 'package:phaseout/models/app_usage_model.dart';
import 'package:phaseout/utils/constants.dart';

void main() {

  // ── AppConstants ─────────────────────────────────────────
  group('AppConstants', () {
    test('package name is correct', () {
      expect(AppConstants.packageName, 'com.brightdev.phaseout');
    });

    test('dbVersion is 5', () {
      expect(AppConstants.dbVersion, 5);
    });

    test('all action strings are non-empty', () {
      expect(AppConstants.actionStopMedia.isNotEmpty,      true);
      expect(AppConstants.actionDoNotDisturb.isNotEmpty,   true);
      expect(AppConstants.actionDimBrightness.isNotEmpty,  true);
      expect(AppConstants.actionGoHome.isNotEmpty,         true);
      expect(AppConstants.actionSendNotification.isNotEmpty, true);
    });

    test('channel aliases resolve correctly', () {
      expect(AppConstants.channelAlerts,    AppConstants.notifChannelAlert);
      expect(AppConstants.channelReminders, AppConstants.notifChannelReminder);
    });

    test('allDays contains 7 days', () {
      expect(AppConstants.allDays.length, 7);
    });
  });

  // ── ScheduleModel ─────────────────────────────────────────
  group('ScheduleModel', () {
    final schedule = ScheduleModel(
      name:        'Bedtime',
      triggerTime: const TimeOfDay(hour: 22, minute: 30),
      daysOfWeek:  [1, 2, 3, 4, 5],
      actions:     [AppConstants.actionStopMedia, AppConstants.actionDoNotDisturb],
      enabled:     true,
      createdAt:   DateTime(2026, 1, 1),
    );

    test('serialises to map and back', () {
      final map  = schedule.toMap();
      final back = ScheduleModel.fromMap({...map, 'id': 1});
      expect(back.name,              schedule.name);
      expect(back.triggerTime.hour,  schedule.triggerTime.hour);
      expect(back.triggerTime.minute,schedule.triggerTime.minute);
      expect(back.daysOfWeek,        schedule.daysOfWeek);
      expect(back.actions,           schedule.actions);
      expect(back.enabled,           schedule.enabled);
    });

    test('wakeTime round-trips correctly when set', () {
      final withWake = schedule.copyWith(
          wakeTime: const TimeOfDay(hour: 7, minute: 0));
      final map  = withWake.toMap();
      final back = ScheduleModel.fromMap({...map, 'id': 2});
      expect(back.wakeTime?.hour,   7);
      expect(back.wakeTime?.minute, 0);
    });

    test('wakeTime is null when not set', () {
      final map  = schedule.toMap();
      final back = ScheduleModel.fromMap({...map, 'id': 3});
      expect(back.wakeTime, isNull);
    });

    test('copyWith enabled toggles correctly', () {
      final disabled = schedule.copyWith(enabled: false);
      expect(disabled.enabled, false);
      expect(disabled.name, schedule.name);
    });
  });

  // ── AppUsageModel ─────────────────────────────────────────
  group('AppUsageModel', () {
    test('todayString returns valid date format', () {
      final today = AppUsageModel.todayString();
      expect(today.isNotEmpty, true);
      // Should be YYYY-MM-DD
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(today), true);
    });

    test('formatDate produces consistent output', () {
      final date = DateTime(2026, 5, 7);
      final str  = AppUsageModel.formatDate(date);
      expect(str, '2026-05-07');
    });

    test('isOverLimit is false when no limit set', () {
      const app = AppUsageModel(
        packageName:  'com.example.app',
        appLabel:     'Example',
        date:         '2026-05-07',
        usageMinutes: 120,
      );
      expect(app.isOverLimit, false);
    });

    test('isOverLimit is true when usage exceeds limit', () {
      const app = AppUsageModel(
        packageName:  'com.example.app',
        appLabel:     'Example',
        date:         '2026-05-07',
        usageMinutes: 90,
        limitMinutes: 60,
      );
      expect(app.isOverLimit, true);
    });

    test('isOverLimit is false when usage is under limit', () {
      const app = AppUsageModel(
        packageName:  'com.example.app',
        appLabel:     'Example',
        date:         '2026-05-07',
        usageMinutes: 30,
        limitMinutes: 60,
      );
      expect(app.isOverLimit, false);
    });

    test('serialises to map and back', () {
      const app = AppUsageModel(
        packageName:  'com.example.app',
        appLabel:     'Example',
        date:         '2026-05-07',
        usageMinutes: 45,
        limitMinutes: 60,
      );
      final map  = app.toMap();
      final back = AppUsageModel.fromMap({...map, 'id': 1});
      expect(back.packageName,  app.packageName);
      expect(back.appLabel,     app.appLabel);
      expect(back.usageMinutes, app.usageMinutes);
      expect(back.limitMinutes, app.limitMinutes);
    });
  });

  // ── Schedule action bundles ───────────────────────────────
  group('Bundle detection logic', () {
    test('sleep mode actions are distinct', () {
      const sleepActions = [
        AppConstants.actionStopMedia,
        AppConstants.actionDimBrightness,
        AppConstants.actionDoNotDisturb,
      ];
      expect(sleepActions.toSet().length, 3);
    });

    test('no action string is empty', () {
      final allActions = [
        AppConstants.actionStopMedia,
        AppConstants.actionSendNotification,
        AppConstants.actionLaunchApp,
        AppConstants.actionActivateFocus,
        AppConstants.actionGoHome,
        AppConstants.actionDoNotDisturb,
        AppConstants.actionDimBrightness,
        AppConstants.actionSetMorningAlarm,
      ];
      for (final a in allActions) {
        expect(a.isNotEmpty, true, reason: '$a should not be empty');
      }
    });
  });
}