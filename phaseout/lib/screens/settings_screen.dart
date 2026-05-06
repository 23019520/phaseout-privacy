// ─────────────────────────────────────────────────────────────
//  lib/screens/settings_screen.dart
//
//  FIX #8:
//  - Developer: Dzivhani Unarine
//  - Privacy policy URL: 23019520.github.io/phaseout-privacy
//  - Custom notification sound picker added
//  - Version updated to 1.0.0 — Final
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_theme.dart';
import '../db/database_helper.dart';
import '../services/background_service.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';
import 'permissions_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool    _bgsRunning       = false;
  bool    _analyticsEnabled = true;
  String? _customSoundUri;
  String? _customSoundLabel;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final bgs       = await BackgroundService.isRunning();
    final prefs     = await SharedPreferences.getInstance();
    final analytics = prefs.getBool(AppConstants.prefAnalyticsEnabled) ?? true;
    final sound     = await NotificationService.getCustomSound();
    if (mounted) {
      setState(() {
        _bgsRunning       = bgs;
        _analyticsEnabled = analytics;
        _customSoundUri   = sound;
        _customSoundLabel = sound != null ? 'Custom sound set' : null;
      });
    }
  }

  Future<void> _toggleAnalytics(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefAnalyticsEnabled, v);
    setState(() => _analyticsEnabled = v);
  }

  Future<void> _pickCustomSound() async {
    final uri = await NotificationService.pickSound();
    if (uri != null && mounted) {
      setState(() {
        _customSoundUri   = uri;
        _customSoundLabel = 'Custom sound set';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Custom notification sound saved.')));
      }
    }
  }

  Future<void> _clearCustomSound() async {
    await NotificationService.clearCustomSound();
    setState(() { _customSoundUri = null; _customSoundLabel = null; });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restored default notification sound.')));
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final url = Uri.parse('https://23019520.github.io/phaseout-privacy');
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  Future<void> _resetOnboarding() async {
    final ok = await _confirm(context, 'Reset onboarding',
        'This will show the onboarding flow next time you open the app.',
        confirmLabel: 'Reset', confirmColor: AppTheme.amber);
    if (ok) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.prefOnboardingDone, false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Onboarding reset. Restart the app.')));
      }
    }
  }

  Future<void> _clearAllData() async {
    final ok = await _confirm(context, 'Clear all data',
        'This will delete all schedules, usage history, and settings. This cannot be undone.',
        confirmLabel: 'Delete everything', confirmColor: AppTheme.rose);
    if (ok) {
      await DatabaseHelper.instance.close();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data cleared. Restart the app.')));
      }
    }
  }

  Future<bool> _confirm(BuildContext ctx, String title, String body,
      {required String confirmLabel, required Color confirmColor}) async {
    return await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textSecond))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel,
                  style: TextStyle(color: confirmColor))),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [

          _Section('Background service', children: [
            _Tile(
              icon: Icons.circle,
              iconColor: _bgsRunning ? AppTheme.success : AppTheme.rose,
              title: 'Service status',
              subtitle: _bgsRunning ? 'Running — schedules are active' : 'Stopped',
              trailing: _bgsRunning
                  ? _TextAction('Stop', AppTheme.rose, () async {
                      await BackgroundService.stop();
                      await Future.delayed(const Duration(seconds: 1));
                      _load();
                    })
                  : _TextAction('Start', AppTheme.success, () async {
                      await BackgroundService.start();
                      await Future.delayed(const Duration(seconds: 2));
                      _load();
                    }),
            ),
          ]),

          _Section('Permissions', children: [
            _Tile(
              icon: Icons.security_rounded, iconColor: AppTheme.blue,
              title: 'Manage permissions',
              subtitle: 'Check and grant required permissions',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PermissionsScreen())),
            ),
          ]),

          // FIX #2 — Custom notification sound
          _Section('Notifications', children: [
            _Tile(
              icon: Icons.music_note_rounded, iconColor: AppTheme.tealLight,
              title: 'Notification sound',
              subtitle: _customSoundLabel ?? 'Using default system sound',
              onTap: _pickCustomSound,
            ),
            if (_customSoundUri != null)
              _Tile(
                icon: Icons.restore_rounded, iconColor: AppTheme.textSecond,
                title: 'Restore default sound',
                subtitle: 'Remove custom sound',
                onTap: _clearCustomSound,
              ),
          ]),

          _Section('Privacy', children: [
            _Tile(
              icon: Icons.analytics_rounded, iconColor: AppTheme.teal,
              title: 'Crash analytics',
              subtitle: 'Share anonymous crash data to improve PhaseOut',
              trailing: Switch(
                  value: _analyticsEnabled, onChanged: _toggleAnalytics),
            ),
            _Tile(
              icon: Icons.policy_rounded, iconColor: AppTheme.textSecond,
              title: 'Privacy Policy',
              subtitle: '23019520.github.io/phaseout-privacy',
              onTap: _openPrivacyPolicy,
            ),
          ]),

          _Section('Data', children: [
            _Tile(
              icon: Icons.restart_alt_rounded, iconColor: AppTheme.amber,
              title: 'Reset onboarding',
              subtitle: 'Show the intro screens again on next launch',
              onTap: _resetOnboarding,
            ),
            _Tile(
              icon: Icons.delete_forever_rounded, iconColor: AppTheme.rose,
              title: 'Clear all data',
              subtitle: 'Delete all schedules, usage history, and settings',
              onTap: _clearAllData,
            ),
          ]),

          // FIX #8 — Developer info
          const _Section('About', children: [
            _Tile(
              icon: Icons.info_outline_rounded, iconColor: AppTheme.textSecond,
              title: 'Version', subtitle: '1.0.0 — Final'),
            _Tile(
              icon: Icons.code_rounded, iconColor: AppTheme.textSecond,
              title: 'Developer', subtitle: 'Dzivhani Unarine'),
            _Tile(
              icon: Icons.business_rounded, iconColor: AppTheme.textSecond,
              title: 'Package', subtitle: AppConstants.packageName),
          ]),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  final String label; final Color color; final VoidCallback onTap;
  const _TextAction(this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Text(label,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)));
}

class _Section extends StatelessWidget {
  final String title; final List<Widget> children;
  const _Section(this.title, {required this.children});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text(title.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                color: AppTheme.textHint, letterSpacing: 1.2))),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border)),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Divider(height: 0, indent: 60, color: AppTheme.border),
          ],
        ]),
      ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  final IconData icon; final Color iconColor;
  final String title, subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  const _Tile({required this.icon, required this.iconColor,
      required this.title, required this.subtitle,
      this.onTap, this.trailing});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(width: 34, height: 34,
        decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, color: iconColor, size: 17)),
      title: Text(title, style: const TextStyle(fontSize: 13,
          fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
      subtitle: Text(subtitle, style: const TextStyle(
          fontSize: 11, color: AppTheme.textHint)),
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right_rounded,
                  size: 16, color: AppTheme.textHint)
              : null),
      onTap: onTap,
    );
  }
}