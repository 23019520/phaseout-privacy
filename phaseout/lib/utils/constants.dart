// ─────────────────────────────────────────────────────────────
//  lib/utils/constants.dart
//  PhaseOut — Central constants registry
//
//  ADDED (bottom of file):
//  - channelAlerts, channelReminders, channelPreAction
//  - prefCustomSoundUri
//  - actionFireNow, actionSnooze30, actionSkipToday
// ─────────────────────────────────────────────────────────────

class AppConstants {

  AppConstants._();

  // ── App identity ───────────────────────────────────────────
  static const String appName     = 'PhaseOut';
  static const String packageName = 'com.brightdev.phaseout';

  // ── MethodChannel names ────────────────────────────────────
  static const String mediaChannel   = 'com.brightdev.phaseout/media';
  static const String batteryChannel = 'com.brightdev.phaseout/battery';
  static const String usageChannel   = 'com.brightdev.phaseout/usage';

  // ── MethodChannel method names ─────────────────────────────
  static const String methodStopAllMedia       = 'stopAllMedia';
  static const String methodReleaseAudioFocus  = 'releaseAudioFocus';
  static const String methodLaunchApp          = 'launchApp';
  static const String methodGetDischargeRate   = 'getDischargeRate';
  static const String methodGetBatteryCapacity = 'getBatteryCapacity';
  static const String methodGetUsageStats      = 'getUsageStats';

  // ── Database ───────────────────────────────────────────────
  static const String dbName    = 'phaseout.db';
  static const int    dbVersion = 5;

  // ── Table names ────────────────────────────────────────────
  static const String tableSchedules     = 'schedules';
  static const String tableScenarios     = 'scenarios';
  static const String tableAppUsage      = 'app_usage_daily';
  static const String tableBattery       = 'battery_snapshots';
  static const String tableUsageEvents   = 'usage_events';
  static const String tableFocusSessions = 'focus_sessions';
  static const String tableDayProfiles   = 'day_profiles';
  
  // ── Notification channel IDs ───────────────────────────────
  static const String notifChannelBGS        = 'phaseout_bgs';
  static const String notifChannelWindDown   = 'phaseout_winddown';
  static const String notifChannelReminder   = 'phaseout_reminder';
  static const String notifChannelAlert      = 'phaseout_alert';
  static const String notifChannelUsageAlert = 'phaseout_usage_alert';

  // Aliases used by notification_service.dart and pre_action_overlay_service
  static const String channelAlerts    = notifChannelAlert;
  static const String channelReminders = notifChannelReminder;
  static const String channelPreAction = 'phaseout_preaction';

  // ── Notification channel names ─────────────────────────────
  static const String notifChannelBGSName       = 'PhaseOut Background Service';
  static const String notifChannelWindDownName   = 'Sleep Wind-Down';
  static const String notifChannelReminderName   = 'Reminders';
  static const String notifChannelAlertName      = 'Alerts';
  static const String notifChannelUsageAlertName = 'Usage Limit Alerts';

  // ── Notification IDs ──────────────────────────────────────
  static const int notifIdBGS        = 1;
  static const int notifIdWindDown   = 2;
  static const int notifIdReminder   = 3;
  static const int notifIdAlert      = 4;
  static const int notifIdUsageAlert = 5;

  // ── Background service ─────────────────────────────────────
  static const int    bgTickIntervalSeconds = 60;
  static const String bgServiceKey         = 'phaseout_bg_service';

  // ── Scheduler actions ──────────────────────────────────────
  static const String actionStopMedia        = 'stop_media';
  static const String actionSendNotification = 'send_notification';
  static const String actionLaunchApp        = 'launch_app';
  static const String actionActivateFocus    = 'activate_focus';

  static const String actionGoHome          = 'go_home';
  static const String actionDoNotDisturb    = 'do_not_disturb';
  static const String actionDimBrightness   = 'dim_brightness';
  static const String actionSetMorningAlarm = 'set_morning_alarm';

  // Service intent actions (used by pre_action_overlay_service)
  static const String actionFireNow   = 'ACTION_FIRE_NOW';
  static const String actionSnooze30  = 'ACTION_SNOOZE_30';
  static const String actionSkipToday = 'ACTION_SKIP_TODAY';

  // ── Usage event types ──────────────────────────────────────
  static const String eventActionFired         = 'action_fired';
  static const String eventSuggestionShown     = 'suggestion_shown';
  static const String eventSuggestionAccepted  = 'suggestion_accepted';
  static const String eventSuggestionDismissed = 'suggestion_dismissed';

  // ── Usage event outcomes ───────────────────────────────────
  static const String outcomeSuccess = 'success';
  static const String outcomeSkipped = 'skipped';
  static const String outcomeFailed  = 'failed';

  // ── SharedPreferences keys ─────────────────────────────────
  static const String prefOnboardingDone    = 'onboarding_done';
  static const String prefDarkMode          = 'dark_mode';
  static const String prefAnalyticsEnabled  = 'analytics_enabled';
  static const String prefNlpCallsToday     = 'nlp_calls_today';
  static const String prefNlpCallsDate      = 'nlp_calls_date';
  static const String prefCustomSoundUri    = 'custom_sound_uri';

  // ── NLP ────────────────────────────────────────────────────
  static const int nlpDailyCallLimit = 10;

  // ── Battery ────────────────────────────────────────────────
  static const int batteryPollIntervalSeconds       = 300;
  static const int batteryActivePollIntervalSeconds = 60;
  static const int mlRollingWindowDays              = 28;

  // ── Focus mode ─────────────────────────────────────────────
  static const int focusPollIntervalSeconds = 1;

  // ── Audio timer ────────────────────────────────────────────
  static const int audioTimerMinMinutes = 5;
  static const int audioTimerMaxMinutes = 120;

  // ── Days of week ───────────────────────────────────────────
  static const List<int> weekdays = [1, 2, 3, 4, 5];
  static const List<int> weekend  = [6, 7];
  static const List<int> allDays  = [1, 2, 3, 4, 5, 6, 7];

  static const List<String> dayAbbreviations = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  static const List<String> dayLetters = [
    'M', 'T', 'W', 'T', 'F', 'S', 'S',
  ];
}