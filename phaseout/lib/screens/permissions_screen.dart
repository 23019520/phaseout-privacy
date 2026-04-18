// ─────────────────────────────────────────────────────────────
//  lib/screens/permissions_screen.dart  (v2)
//  PhaseOut — All permissions including new bedtime extras
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app_theme.dart';
import '../channels/usage_channel.dart';
import '../channels/media_channel.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});
  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {

  bool _notifications    = false;
  bool _usageStats       = false;
  final bool _notifListener    = false;
  bool _batteryOpt       = false;
  bool _overlay          = false;
  final bool _doNotDisturb     = false;
  final bool _writeSettings    = false;

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
    if (state == AppLifecycleState.resumed) _checkAll();
  }

  Future<void> _checkAll() async {
    final notifs   = await Permission.notification.isGranted;
    final usage    = await UsageChannel.hasUsagePermission();
    final battery  = await Permission.ignoreBatteryOptimizations.isGranted;
    final overlay  = await Permission.systemAlertWindow.isGranted;

    if (mounted) {
      setState(() {
        _notifications = notifs;
        _usageStats    = usage;
        _batteryOpt    = battery;
        _overlay       = overlay;
      });
    }

    // These can't be checked cleanly from Dart — assume granted
    // if user has been through the flow
    // For a more robust check we'd use a MethodChannel
  }

  bool get _requiredGranted =>
      _notifications && _usageStats && _batteryOpt;

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
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          // Status banner
          Container(
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
              Expanded(child: Text(
                _requiredGranted
                    ? 'All required permissions granted.'
                    : 'Some required permissions are missing.',
                style: TextStyle(
                  fontSize: 12, height: 1.5,
                  color: _requiredGranted
                      ? AppTheme.success
                      : AppTheme.warning,
                ),
              )),
            ]),
          ),

          const SizedBox(height: 24),
          const _SectionHeader('Required'),

          _PermRow(
            icon:    Icons.notifications_rounded,
            iconBg:  const Color(0xFF3B82F6),
            title:   'Notifications',
            desc:    'Wind-down alerts and usage warnings',
            granted: _notifications,
            onGrant: () async {
              await Permission.notification.request();
              _checkAll();
            },
          ),
          _PermRow(
            icon:    Icons.bar_chart_rounded,
            iconBg:  AppTheme.tealLight,
            title:   'Usage Access',
            desc:    'Per-app screen time tracking and limits',
            granted: _usageStats,
            onGrant: () => UsageChannel.openUsageSettings(),
          ),
          _PermRow(
            icon:    Icons.speaker_rounded,
            iconBg:  const Color(0xFFA78BFA),
            title:   'Notification Access',
            desc:    'Stop music and media from any app',
            granted: _notifListener,
            onGrant: () => MediaChannel.openNotificationSettings(),
          ),
          _PermRow(
            icon:    Icons.battery_charging_full_rounded,
            iconBg:  AppTheme.success,
            title:   'Battery Optimisation',
            desc:    'Keeps PhaseOut alive overnight without Doze killing it',
            granted: _batteryOpt,
            onGrant: () async {
              await Permission.ignoreBatteryOptimizations.request();
              _checkAll();
            },
          ),

          const SizedBox(height: 20),
          const _SectionHeader('Bedtime extras (optional)'),

          _PermRow(
            icon:    Icons.picture_in_picture_rounded,
            iconBg:  const Color(0xFF60A5FA),
            title:   'Display over other apps',
            desc:    'Shows focus lock overlay above TikTok, Instagram, etc.',
            granted: _overlay,
            required: false,
            onGrant: () async {
              await Permission.systemAlertWindow.request();
              _checkAll();
            },
          ),
          _PermRow(
            icon:    Icons.do_not_disturb_rounded,
            iconBg:  AppTheme.amber,
            title:   'Do Not Disturb access',
            desc:    'Enables DND at bedtime, restores settings in morning',
            granted: _doNotDisturb,
            required: false,
            onGrant: () {
              // Open DND access settings
              // No Flutter plugin for this — guide user
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                  'Go to Settings → Apps → Special access → Do Not Disturb → PhaseOut → Allow'),
              ));
            },
          ),
          _PermRow(
            icon:    Icons.brightness_medium_rounded,
            iconBg:  const Color(0xFFF472B6),
            title:   'Modify system settings',
            desc:    'Dims screen brightness at bedtime, restores in morning',
            granted: _writeSettings,
            required: false,
            onGrant: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                  'Go to Settings → Apps → Special access → Modify system settings → PhaseOut → Allow'),
              ));
            },
          ),

          const SizedBox(height: 20),
          const Text(
            'Optional permissions improve PhaseOut\'s bedtime features but are not required for basic scheduling and usage tracking.',
            style: TextStyle(
                fontSize: 11, color: AppTheme.textHint, height: 1.6),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10, fontWeight: FontWeight.w600,
          color: AppTheme.textHint, letterSpacing: 1.2)),
    );
  }
}

class _PermRow extends StatelessWidget {
  final IconData     icon;
  final Color        iconBg;
  final String       title;
  final String       desc;
  final bool         granted;
  final bool         required;
  final VoidCallback onGrant;

  const _PermRow({
    required this.icon, required this.iconBg,
    required this.title, required this.desc,
    required this.granted, required this.onGrant,
    this.required = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: iconBg.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconBg, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary)),
            const SizedBox(height: 2),
            Text(desc, style: const TextStyle(
              fontSize: 10, color: AppTheme.textSecond, height: 1.4)),
          ],
        )),
        const SizedBox(width: 10),
        granted
            ? Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text('Granted',
                  style: TextStyle(
                    fontSize: 10, color: AppTheme.success,
                    fontWeight: FontWeight.w600)),
              )
            : GestureDetector(
                onTap: onGrant,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: AppTheme.amber.withValues(alpha: 0.3)),
                  ),
                  child: const Text('Grant',
                    style: TextStyle(
                      fontSize: 10, color: AppTheme.amber,
                      fontWeight: FontWeight.w600)),
                ),
              ),
      ]),
    );
  }
}