// ─────────────────────────────────────────────────────────────
//  lib/utils/constants.dart
//  PhaseOut — Central constants registry
//  All magic strings and numbers live here. Import this file
//  everywhere instead of hardcoding values inline.
// ─────────────────────────────────────────────────────────────

class AppConstants {

  AppConstants._(); // prevent instantiation

  // ── App identity ───────────────────────────────────────────
  static const String appName       = 'PhaseOut';
  static const String packageName   = 'com.brightdev.phaseout';

  // ── MethodChannel names ────────────────────────────────────
  // Must match the channel name registered in MainActivity.kt
  static const String mediaChannel   = 'com.brightdev.phaseout/media';
  static const String batteryChannel = 'com.brightdev.phaseout/battery';
  static const String usageChannel   = 'com.brightdev.phaseout/usage';

  // ── MethodChannel method names ─────────────────────────────
  static const String methodStopAllMedia      = 'stopAllMedia';
  static const String methodReleaseAudioFocus = 'releaseAudioFocus';
  static const String methodLaunchApp         = 'launchApp';
  static const String methodGetDischargeRate  = 'getDischargeRate';
  static const String methodGetBatteryCapacity= 'getBatteryCapacity';
  static const String methodGetUsageStats     = 'getUsageStats';

  // ── Database ───────────────────────────────────────────────
  static const String dbName        = 'phaseout.db';
  static const int    dbVersion     = 2;

  // ── Table names ────────────────────────────────────────────
  static const String tableSchedules    = 'schedules';
  static const String tableScenarios    = 'scenarios';
  static const String tableAppUsage     = 'app_usage_daily';
  static const String tableBattery      = 'battery_snapshots';
  static const String tableUsageEvents  = 'usage_events';

  // ── Notification channel IDs ───────────────────────────────
  static const String notifChannelBGS       = 'phaseout_bgs';
  static const String notifChannelWindDown  = 'phaseout_winddown';
  static const String notifChannelReminder  = 'phaseout_reminder';
  static const String notifChannelAlert     = 'phaseout_alert';
static const int notifIdUsageAlert = 5;
  // ── Notification channel names (shown in system settings) ──
  static const String notifChannelBGSName      = 'PhaseOut Background Service';
  static const String notifChannelWindDownName = 'Sleep Wind-Down';
  static const String notifChannelReminderName = 'Reminders';
  static const String notifChannelAlertName    = 'Alerts';
  static const String notifChannelUsageAlert     = 'phaseout_usage_alert';
static const String notifChannelUsageAlertName = 'Usage Limit Alerts';
  // ── Notification IDs ──────────────────────────────────────
  static const int notifIdBGS       = 1;
  static const int notifIdWindDown  = 2;
  static const int notifIdReminder  = 3;
  static const int notifIdAlert     = 4;

  // ── Background service ─────────────────────────────────────
  static const int    bgTickIntervalSeconds = 60;
  static const String bgServiceKey          = 'phaseout_bg_service';

  // ── Scheduler ─────────────────────────────────────────────
  // Action type strings stored in schedule JSON
  static const String actionStopMedia         = 'stop_media';
  static const String actionSendNotification  = 'send_notification';
  static const String actionLaunchApp         = 'launch_app';
  static const String actionActivateFocus     = 'activate_focus';

  // ── Usage event types ──────────────────────────────────────
  static const String eventActionFired        = 'action_fired';
  static const String eventSuggestionShown    = 'suggestion_shown';
  static const String eventSuggestionAccepted = 'suggestion_accepted';
  static const String eventSuggestionDismissed= 'suggestion_dismissed';

  // ── Usage event outcomes ───────────────────────────────────
  static const String outcomeSuccess  = 'success';
  static const String outcomeSkipped  = 'skipped';
  static const String outcomeFailed   = 'failed';

  // ── SharedPreferences keys ─────────────────────────────────
  static const String prefOnboardingDone   = 'onboarding_done';
  static const String prefDarkMode         = 'dark_mode';
  static const String prefAnalyticsEnabled = 'analytics_enabled';
  static const String prefNlpCallsToday    = 'nlp_calls_today';
  static const String prefNlpCallsDate     = 'nlp_calls_date';

  // ── NLP ────────────────────────────────────────────────────
  static const int nlpDailyCallLimit = 10;

  // ── Battery ────────────────────────────────────────────────
  static const int batteryPollIntervalSeconds       = 300; // 5 minutes idle
  static const int batteryActivePollIntervalSeconds = 60;  // 1 minute when trigger active
  static const int mlRollingWindowDays              = 28;

  // ── Focus mode ─────────────────────────────────────────────
  static const int focusPollIntervalSeconds = 1;

  // ── Days of week ───────────────────────────────────────────
  // Dart DateTime.weekday: 1=Mon … 7=Sun
  static const List<int> weekdays  = [1, 2, 3, 4, 5];
  static const List<int> weekend   = [6, 7];
  static const List<int> allDays   = [1, 2, 3, 4, 5, 6, 7];

  static const List<String> dayAbbreviations = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];

  static const List<String> dayLetters = [
    'M', 'T', 'W', 'T', 'F', 'S', 'S'
  ];
}
