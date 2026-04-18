// ─────────────────────────────────────────────────────────────
//  lib/screens/settings_screen.dart  — PhaseOut v1.0 final
//
//  Reworked: cleaner layout, proper section grouping,
//  removed redundant items, improved copy throughout.
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../db/database_helper.dart';
import '../services/background_service.dart';
import '../utils/constants.dart';
import 'permissions_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {

  bool _bgsRunning       = false;
  bool _analyticsEnabled = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final bgs       = await BackgroundService.isRunning();
    final prefs     = await SharedPreferences.getInstance();
    final analytics = prefs.getBool(AppConstants.prefAnalyticsEnabled) ?? true;
    if (mounted) setState(() {
      _bgsRunning       = bgs;
      _analyticsEnabled = analytics;
    });
  }

  Future<void> _toggleAnalytics(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefAnalyticsEnabled, v);
    setState(() => _analyticsEnabled = v);
  }

  Future<void> _restartBgs() async {
    await BackgroundService.stop();
    await Future.delayed(const Duration(seconds: 1));
    await BackgroundService.start();
    await Future.delayed(const Duration(seconds: 2));
    _load();
  }

  Future<void> _clearAllData() async {
    final ok = await _confirm(
      'Clear all data',
      'This deletes all schedules, usage history, battery data, and settings. It cannot be undone.',
      confirmLabel: 'Delete everything',
      confirmColor: AppTheme.danger,
    );
    if (!ok) return;
    await DatabaseHelper.instance.close();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data cleared. Please restart the app.')));
    }
  }

  Future<bool> _confirm(
    String title,
    String body, {
    required String confirmLabel,
    required Color  confirmColor,
  }) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(
            color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(body,
            style: const TextStyle(color: AppTheme.textSecond, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecond))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel,
                style: TextStyle(color: confirmColor, fontWeight: FontWeight.w600))),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [

          // ── Service status ────────────────────────────────
          _Section('Background service', children: [
            _Tile(
              icon:      Icons.circle,
              iconColor: _bgsRunning ? AppTheme.success : AppTheme.danger,
              title:     'Service status',
              subtitle:  _bgsRunning
                  ? 'Running — schedules will fire automatically'
                  : 'Stopped — tap to restart',
              trailing: _bgsRunning
                  ? _Tag('Active', AppTheme.success)
                  : _TextBtn('Restart', AppTheme.amber, _restartBgs),
            ),
          ]),

          // ── Permissions ───────────────────────────────────
          _Section('Permissions', children: [
            _Tile(
              icon:      Icons.security_rounded,
              iconColor: AppTheme.accentLight,
              title:     'Manage permissions',
              subtitle:  'Notification access, usage stats, overlay and more',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PermissionsScreen())),
            ),
          ]),

          // ── Privacy ───────────────────────────────────────
          _Section('Privacy', children: [
            _Tile(
              icon:      Icons.analytics_rounded,
              iconColor: AppTheme.tealLight,
              title:     'Crash analytics',
              subtitle:  'Send anonymous crash reports to help fix bugs',
              trailing:  Switch(
                value:     _analyticsEnabled,
                onChanged: _toggleAnalytics,
              ),
            ),
          ]),

          // ── About ─────────────────────────────────────────
          _Section('About', children: [
            const _Tile(
              icon:      Icons.info_outline_rounded,
              iconColor: AppTheme.textSecond,
              title:     'Version',
              subtitle:  '1.0.0',
            ),
            const _Tile(
              icon:      Icons.code_rounded,
              iconColor: AppTheme.textSecond,
              title:     'Developer',
              subtitle:  'BrightDev',
            ),
            const _Tile(
              icon:      Icons.shield_outlined,
              iconColor: AppTheme.textSecond,
              title:     'Privacy policy',
              subtitle:  'brightdev.github.io/phaseout-privacy',
            ),
          ]),

          // ── Danger zone ───────────────────────────────────
          _Section('Data', children: [
            _Tile(
              icon:      Icons.delete_forever_rounded,
              iconColor: AppTheme.danger,
              title:     'Clear all data',
              subtitle:  'Delete schedules, usage history, and all settings',
              onTap:     _clearAllData,
            ),
          ]),

          const SizedBox(height: 32),

          // Footer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'PhaseOut v1.0 · com.brightdev.phaseout',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textHint),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Section wrapper ───────────────────────────────────────────
class _Section extends StatelessWidget {
  final String       title;
  final List<Widget> children;
  const _Section(this.title, {required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text(title.toUpperCase(),
          style: const TextStyle(
              fontSize:   10,
              fontWeight: FontWeight.w600,
              color:      AppTheme.textHint,
              letterSpacing: 1.2)),
      ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color:        AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
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

// ── Tile ──────────────────────────────────────────────────────
class _Tile extends StatelessWidget {
  final IconData     icon;
  final Color        iconColor;
  final String       title;
  final String       subtitle;
  final VoidCallback? onTap;
  final Widget?       trailing;
  const _Tile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color:        iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, color: iconColor, size: 17),
      ),
      title: Text(title,
        style: const TextStyle(fontSize: 13,
            fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
      subtitle: Text(subtitle,
        style: const TextStyle(fontSize: 11, color: AppTheme.textHint, height: 1.4)),
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right_rounded,
                  size: 16, color: AppTheme.textHint)
              : null),
      onTap: onTap,
    );
  }
}

class _Tag extends StatelessWidget {
  final String label; final Color color;
  const _Tag(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(99)),
    child: Text(label,
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)));
}

class _TextBtn extends StatelessWidget {
  final String label; final Color color; final VoidCallback onTap;
  const _TextBtn(this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Text(label,
      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)));
}