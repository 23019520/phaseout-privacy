// ─────────────────────────────────────────────────────────────
//  lib/screens/permissions_screen.dart  — v5
//
//  ROOT CAUSE OF "stuck on OK" BUG:
//  1. Battery optimisation: permission_handler's request() shows
//     a system dialog but is silently ignored by most Android OEMs
//     (Xiaomi, Samsung, Huawei etc.). Must open Settings directly.
//  2. System alert window: permission_handler's
//     systemAlertWindow.request() is a documented no-op on
//     Android 11+. Must open Settings.ACTION_MANAGE_OVERLAY_PERMISSION.
//  3. onGrant was typed VoidCallback (sync) so async navigation
//     futures were dropped silently — _openSpecialSettings() returned
//     a Future<void> that nothing awaited.
//
//  FIXES:
//  - onGrant changed to Future<void> Function() (async-aware)
//  - Battery optimisation → MediaChannel.openBatterySettings()
//  - System alert window  → MediaChannel.openOverlaySettings()
//  - Notifications: request() first, fall back to app settings
//    if permanently denied
//  - All grant handlers are proper async lambdas
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app_theme.dart';
import '../channels/media_channel.dart';
import '../channels/usage_channel.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});
  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {

  bool _notifications  = false;
  bool _usageStats     = false;
  bool _notifListener  = false;
  bool _batteryOpt     = false;
  bool _overlay        = false;
  bool _doNotDisturb   = false;
  bool _writeSettings  = false;

  // Tracks which row is currently in-progress so we can show
  // a loading indicator instead of the Grant button
  String? _loading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check whenever the user comes back from Settings
      _checkAll();
    }
  }

  Future<void> _checkAll() async {
    final notifs   = await Permission.notification.isGranted;
    final usage    = await UsageChannel.hasUsagePermission();
    final battery  = await Permission.ignoreBatteryOptimizations.isGranted;
    final overlay  = await Permission.systemAlertWindow.isGranted;
    final nls      = await MediaChannel.isNotificationListenerEnabled();
    final dnd      = await MediaChannel.isDndAccessGranted();
    final write    = await MediaChannel.isWriteSettingsGranted();

    if (mounted) {
      setState(() {
        _notifications = notifs;
        _usageStats    = usage;
        _notifListener = nls;
        _batteryOpt    = battery;
        _overlay       = overlay;
        _doNotDisturb  = dnd;
        _writeSettings = write;
        _loading       = null;
      });
    }
  }

  // ── Grant handler ─────────────────────────────────────────
  // Shows a spinner on the tapped row while the settings page
  // opens. Because didChangeAppLifecycleState re-checks on
  // resume, the badge updates automatically when the user
  // comes back from Android Settings.
  Future<void> _grant(String key, Future<void> Function() action) async {
    if (mounted) setState(() => _loading = key);
    // Let the current frame settle before handing off to Android
    await SchedulerBinding.instance.endOfFrame;
    try {
      await action();
    } catch (_) {}
    // If the action returns immediately (e.g. request() dialog)
    // re-check at once. For Settings-based flows the re-check
    // happens in didChangeAppLifecycleState on resume.
    await _checkAll();
  }

  bool get _requiredGranted =>
      _notifications && _usageStats && _notifListener && _batteryOpt;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        title: const Text('Permissions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _checkAll,
            tooltip: 'Re-check',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          // ── Status banner ────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _requiredGranted
                  ? AppTheme.success.withValues(alpha: 0.07)
                  : AppTheme.warning.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _requiredGranted
                    ? AppTheme.success.withValues(alpha: 0.25)
                    : AppTheme.warning.withValues(alpha: 0.25),
              ),
            ),
            child: Row(children: [
              Icon(
                _requiredGranted
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                color: _requiredGranted ? AppTheme.success : AppTheme.warning,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _requiredGranted
                      ? 'All required permissions granted — PhaseOut is fully set up.'
                      : 'Some required permissions are missing.',
                  style: TextStyle(
                    fontSize: 12, height: 1.5,
                    color: _requiredGranted
                        ? AppTheme.success : AppTheme.warning,
                  ),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 24),
          const _SectionLabel('Required'),

          // ── Notifications ────────────────────────────────────
          _PermRow(
            id:      'notifications',
            icon:    Icons.notifications_rounded,
            iconBg:  const Color(0xFF3B82F6),
            title:   'Notifications',
            desc:    'Bedtime reminders and wind-down alerts',
            granted: _notifications,
            loading: _loading == 'notifications',
            onGrant: () => _grant('notifications', () async {
              final status = await Permission.notification.request();
              // If permanently denied, open app settings so the user
              // can manually toggle it — request() won't show a dialog
              if (status.isPermanentlyDenied) await openAppSettings();
            }),
          ),

          // ── Usage access ─────────────────────────────────────
          // Cannot be granted via permission_handler — must open
          // Settings.ACTION_USAGE_ACCESS_SETTINGS directly.
          _PermRow(
            id:      'usage',
            icon:    Icons.bar_chart_rounded,
            iconBg:  AppTheme.tealLight,
            title:   'Usage Access',
            desc:    'Per-app screen time tracking and daily limits',
            granted: _usageStats,
            loading: _loading == 'usage',
            onGrant: () => _grant('usage', UsageChannel.openUsageSettings),
          ),

          // ── Notification listener ─────────────────────────────
          _PermRow(
            id:      'nls',
            icon:    Icons.headphones_rounded,
            iconBg:  const Color(0xFFA78BFA),
            title:   'Notification Access',
            desc:    'Stop music and media from any app at bedtime',
            granted: _notifListener,
            loading: _loading == 'nls',
            hint:    'If media stop still doesn\'t work after granting, toggle the permission OFF then back ON',
            onGrant: () => _grant('nls', MediaChannel.openNotificationSettings),
          ),

          // ── Battery optimisation ─────────────────────────────
          // permission_handler's request() is silently ignored on
          // Samsung, Xiaomi, Huawei etc. Open Settings directly.
          _PermRow(
            id:      'battery',
            icon:    Icons.battery_charging_full_rounded,
            iconBg:  AppTheme.success,
            title:   'Battery Optimisation',
            desc:    'Keeps PhaseOut running overnight without being killed',
            granted: _batteryOpt,
            loading: _loading == 'battery',
            hint:    'Tap Grant, find PhaseOut in the list, and select "Don\'t optimise"',
            onGrant: () => _grant('battery', MediaChannel.openBatterySettings),
          ),

          const SizedBox(height: 24),
          const _SectionLabel('Optional — bedtime extras'),

          // ── Display over other apps ───────────────────────────
          // systemAlertWindow.request() is a no-op on Android 11+.
          // Must open Settings.ACTION_MANAGE_OVERLAY_PERMISSION.
          _PermRow(
            id:      'overlay',
            icon:    Icons.picture_in_picture_rounded,
            iconBg:  const Color(0xFF60A5FA),
            title:   'Display over other apps',
            desc:    'Shows focus lock overlay above blocked apps',
            granted: _overlay,
            loading: _loading == 'overlay',
            onGrant: () => _grant('overlay', MediaChannel.openOverlaySettings),
          ),

          // ── Do Not Disturb ────────────────────────────────────
          _PermRow(
            id:      'dnd',
            icon:    Icons.do_not_disturb_rounded,
            iconBg:  AppTheme.amber,
            title:   'Do Not Disturb access',
            desc:    'Silence all calls and notifications at bedtime',
            granted: _doNotDisturb,
            loading: _loading == 'dnd',
            onGrant: () => _grant('dnd', MediaChannel.openDndSettings),
          ),

          // ── Modify system settings ────────────────────────────
          _PermRow(
            id:      'write',
            icon:    Icons.brightness_medium_rounded,
            iconBg:  const Color(0xFFF472B6),
            title:   'Modify system settings',
            desc:    'Dim screen brightness at bedtime',
            granted: _writeSettings,
            loading: _loading == 'write',
            onGrant: () => _grant('write', MediaChannel.openWriteSettings),
          ),

          const SizedBox(height: 20),
          const Text(
            'Optional permissions unlock bedtime extras. PhaseOut works fully without them — schedules, media stop, usage tracking, and focus mode all run on the required permissions alone.',
            style: TextStyle(fontSize: 11, color: AppTheme.textHint, height: 1.6),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10, fontWeight: FontWeight.w600,
        color: AppTheme.textHint, letterSpacing: 1.2,
      )),
  );
}

// ── Permission row ─────────────────────────────────────────────
// onGrant is now Future<void> Function() so async navigation
// is properly awaited instead of being silently dropped.
class _PermRow extends StatelessWidget {
  final String                    id;
  final IconData                  icon;
  final Color                     iconBg;
  final String                    title;
  final String                    desc;
  final bool                      granted;
  final bool                      loading;
  final String?                   hint;
  final Future<void> Function()   onGrant;

  const _PermRow({
    required this.id,
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.desc,
    required this.granted,
    required this.onGrant,
    this.loading = false,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: granted
              ? AppTheme.success.withValues(alpha: 0.2)
              : AppTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [

            // Icon
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: granted
                    ? AppTheme.success.withValues(alpha: 0.12)
                    : iconBg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                granted ? Icons.check_circle_outline_rounded : icon,
                color: granted ? AppTheme.success : iconBg,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),

            // Title + description
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500,
                    color: granted
                        ? AppTheme.textPrimary
                        : AppTheme.textPrimary,
                  )),
                const SizedBox(height: 2),
                Text(desc,
                  style: const TextStyle(
                    fontSize: 10, color: AppTheme.textSecond, height: 1.4,
                  )),
              ],
            )),
            const SizedBox(width: 10),

            // Right-side: Granted badge / loading / Grant button
            if (granted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text('Granted',
                  style: TextStyle(
                    fontSize: 10, color: AppTheme.success,
                    fontWeight: FontWeight.w600,
                  )),
              )
            else if (loading)
              const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.accentLight),
              )
            else
              GestureDetector(
                onTap: onGrant,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                        color: AppTheme.amber.withValues(alpha: 0.3)),
                  ),
                  child: const Text('Grant',
                    style: TextStyle(
                      fontSize: 10, color: AppTheme.amber,
                      fontWeight: FontWeight.w600,
                    )),
                ),
              ),
          ]),

          // Optional hint
          if (hint != null && !granted) ...[
            const SizedBox(height: 8),
            Row(children: [
              const SizedBox(width: 48),
              Expanded(child: Text(hint!,
                style: const TextStyle(
                  fontSize: 10, color: AppTheme.textHint,
                  fontStyle: FontStyle.italic, height: 1.4,
                ))),
            ]),
          ],
        ],
      ),
    );
  }
}