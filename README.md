<<<<<<< HEAD
# phaseout

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
=======
# PhaseOut — Sleep & Focus

> Wind down. Sleep better.

Android sleep automation app built with Flutter + Kotlin. Schedules fire reliably overnight via a native foreground service — even when the app is fully closed.

**Version 1.0 · April 2026 · `com.brightdev.phaseout`**

---

## What it does

PhaseOut automates your bedtime routine at a time you choose:

- Stops music and audio from any app
- Sends you to the home screen (pauses TikTok, Reels, video apps)
- Enables Do Not Disturb
- Dims screen brightness
- Sets a morning alarm that restores all your settings

Additional features: focus mode with app blocking, per-app usage limits, 7-day busiest-day analytics, and a battery discharge ML model that predicts when your phone will hit 20%.

---

## Architecture

Two-layer design. Kotlin owns all native actions. Flutter owns the UI and database.

| Layer | Responsibility |
|-------|----------------|
| `PhaseOutService.kt` (Kotlin) | Schedule evaluation, media stop, DND, brightness, focus overlay, morning alarm |
| Flutter UI + sqflite | Schedule CRUD, usage display, battery ML chart, settings, navigation |
| SharedPreferences | Cross-layer state: snooze, skip, timer expiry, focus allowlist |
| sqflite v4 | All persistent data — no cloud sync |

---

## Tech Stack

- Flutter 3.x / Dart
- Kotlin — native Android foreground service, WindowManager overlay
- sqflite v4 — local database
- Firebase Crashlytics — anonymous crash reporting only
- `flutter_local_notifications`, `flutter_background_service`, `permission_handler`

---

## First Run

```bash
flutter pub get
# Add google-services.json to android/app/
flutter run --uninstall-first
```

Grant permissions in order: **Notifications → Usage Access → Notification Access → Battery Optimisation**

> Restart the device after granting Notification Access — required for MediaSession binding to work on Samsung and other OEM devices.

---

## Release Build

```bash
flutter build apk --release
flutter install --release
# Output: build/app/outputs/flutter-apk/app-release.apk (~77 MB)
```

---

## Database Schema (v4)

| Table | Since | Key columns |
|-------|-------|-------------|
| `schedules` | v1 | `trigger_time`, `days_of_week`, `actions_json`, `wake_hour`, `wake_minute` |
| `usage_events` | v1 | `event_type`, `reference_id`, `outcome`, `event_time` |
| `app_usage_daily` | v2 | `package_name`, `date`, `usage_minutes`, `limit_minutes` |
| `focus_sessions` | v3 | `start_time`, `end_time`, `allowlist`, `blocked_attempts` |
| `battery_snapshots` | v3 | `level`, `charging`, `recorded_at`, `day_of_week` |

---

## Permissions

| Permission | Required | Purpose |
|------------|----------|---------|
| `POST_NOTIFICATIONS` | Yes | Bedtime reminders and schedule alerts |
| `PACKAGE_USAGE_STATS` | Yes | Per-app screen time tracking |
| Notification Listener Service | Yes | Stop music via MediaSession |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Yes | Keep service alive in Doze mode |
| `SYSTEM_ALERT_WINDOW` | Optional | Focus lock overlay above blocked apps |
| `ACCESS_NOTIFICATION_POLICY` | Optional | Do Not Disturb at bedtime |
| `WRITE_SETTINGS` | Optional | Dim screen brightness |
| `SCHEDULE_EXACT_ALARM` | Optional | Morning wake alarm |

---

## Key Files

| File | Purpose |
|------|---------|
| `PhaseOutService.kt` | Core Kotlin service — schedules, actions, snooze/skip |
| `PhaseOutDatabase.kt` | Direct SQLite reader (no Flutter dependency) |
| `PhaseOutWindowOverlay.kt` | Focus overlay, auto-dismisses after 15 seconds |
| `lib/screens/dashboard_screen.dart` | Home tab with night sky animation |
| `lib/screens/usage_screen.dart` | Daily analytics, busiest days, battery ML |
| `lib/services/battery_prediction_service.dart` | Linear regression over 28-day history |
| `lib/services/battery_advice_service.dart` | Evening charge reminder if battery predicted low overnight |
| `lib/db/database_helper.dart` | sqflite singleton, all CRUD |

---

## Known Limitations

- Notification Access must be re-toggled after reinstall
- Focus detection uses `INTERVAL_BEST` with a ~10-second window — not instant
- DND and brightness require manual special-access grants in Android Settings
- Battery prediction needs ~10 discharge samples (roughly 3 days of data) before it activates
- TikTok and Instagram Reels ignore MediaSession — use "Go to home screen" schedule action instead

---

## v1.1 Roadmap

- AccessibilityService for real-time foreground app detection
- Hard focus blocking (kill process)
- Scenario engine — multi-step bedtime routines
- Home screen widget
- Freemium tier — R49/mo · R399/yr · R999 lifetime

---

## Privacy

All data stays on device. No usage data is uploaded. Crash reports via Firebase Crashlytics contain only error type, device model, and app version.

Privacy policy: [brightdev.github.io/phaseout-privacy](https://brightdev.github.io/phaseout-privacy)

---

*Built by BrightDev · 2026*
>>>>>>> 96fad49ee163435d1c16e9b298459ca0e6b35391
