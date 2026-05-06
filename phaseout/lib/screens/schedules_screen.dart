// ─────────────────────────────────────────────────────────────
//  lib/screens/schedules_screen.dart
//
//  FIXES applied:
//  - Snooze badge: shows "Snoozed +Xm" pill on tile when active
//  - Skip badge: shows "Skipped today" pill on tile when active
//  - Status badges update in real-time after actions
//  - Three-dot menu snooze opens bottom sheet (not loop)
//  - DND permission requested contextually
//  - Bundle-aware icons and colours
//  - Delete sleep timer from within schedules list
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../channels/media_channel.dart';
import '../db/database_helper.dart';
import '../models/schedule_model.dart';
import '../services/schedule_action_service.dart';
import '../utils/constants.dart';
import 'schedule_builder_screen.dart';

class SchedulesScreen extends StatefulWidget {
  const SchedulesScreen({super.key});
  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen>
    with AutomaticKeepAliveClientMixin {

  List<ScheduleModel> _schedules = [];
  // Maps scheduleId → snooze-until ms (0 = not snoozed)
  final Map<int, int>  _snoozeUntil = {};
  // Set of scheduleIds skipped today
  final Set<int>       _skippedIds  = {};
  bool _loading = true;

  @override
  bool get wantKeepAlive => false;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
    _requestDndIfNeeded();
  }

  Future<void> _requestDndIfNeeded() async {
    final granted = await MediaChannel.isDndAccessGranted();
    if (!granted && mounted) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Do Not Disturb access',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
          content: const Text(
            'Schedules can enable DND at bedtime to silence your phone.\n\n'
            'Grant access in the next screen — tap PhaseOut and toggle Allow.',
            style: TextStyle(color: AppTheme.textSecond, fontSize: 13, height: 1.5)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('Not now',
                    style: TextStyle(color: AppTheme.textSecond))),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                MediaChannel.openDndSettings();
              },
              child: const Text('Grant access',
                  style: TextStyle(color: AppTheme.accentLight)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final schedules = await DatabaseHelper.instance.getAllSchedules();

    // Load snooze/skip state for all schedules
    final snoozeUntil = <int, int>{};
    final skippedIds  = <int>{};
    for (final s in schedules) {
      if (s.id == null) continue;
      final until   = await ScheduleActionService.snoozeUntilMs(s.id!);
      final skipped = await ScheduleActionService.isSkippedToday(s.id!);
      if (until != null && until > DateTime.now().millisecondsSinceEpoch) {
        snoozeUntil[s.id!] = until;
      }
      if (skipped) skippedIds.add(s.id!);
    }

    if (mounted) {
      setState(() {
        _schedules   = schedules;
        _loading     = false;
        _snoozeUntil.clear();
        _snoozeUntil.addAll(snoozeUntil);
        _skippedIds.clear();
        _skippedIds.addAll(skippedIds);
      });
    }
  }

  Future<void> _toggle(ScheduleModel s, bool enabled) async {
    await DatabaseHelper.instance.updateSchedule(s.copyWith(enabled: enabled));
    _load();
  }

  Future<void> _delete(ScheduleModel s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete schedule',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Delete "${s.name}"?',
            style: const TextStyle(color: AppTheme.textSecond)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textSecond))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    ) ?? false;
    if (ok && s.id != null) {
      await DatabaseHelper.instance.deleteSchedule(s.id!);
      _load();
    }
  }

  Future<void> _openBuilder({ScheduleModel? existing}) async {
    final result = await Navigator.push<bool>(context,
      MaterialPageRoute(
          builder: (_) => ScheduleBuilderScreen(existing: existing)));
    if (result == true) _load();
  }

  Future<void> _snooze(ScheduleModel s, int minutes) async {
    if (s.id == null) return;
    await ScheduleActionService.snooze(s.id!, minutes);
    // Refresh state to show badge
    await _load();
    if (mounted) {
      _showFeedbackBar('Snoozed "${s.name}" for $minutes min');
    }
  }

  Future<void> _skip(ScheduleModel s) async {
    if (s.id == null) return;
    await ScheduleActionService.skipToday(s.id!);
    await _load();
    if (mounted) {
      _showFeedbackBar('"${s.name}" skipped for today');
    }
  }

  Future<void> _clearSnooze(ScheduleModel s) async {
    if (s.id == null) return;
    await ScheduleActionService.clearSnooze(s.id!);
    await _load();
    if (mounted) {
      _showFeedbackBar('Snooze cleared for "${s.name}"');
    }
  }

  Future<void> _clearSkip(ScheduleModel s) async {
    if (s.id == null) return;
    await ScheduleActionService.clearSkip(s.id!);
    await _load();
    if (mounted) {
      _showFeedbackBar('Skip cleared — "${s.name}" will run today');
    }
  }

  void _showFeedbackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        title: const Text('Schedules'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () => _openBuilder(),
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.accentLight.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.add,
                    color: AppTheme.accentLight, size: 18),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _schedules.isEmpty
              ? _EmptyState(onAdd: () => _openBuilder())
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppTheme.accent,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: _schedules.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final s         = _schedules[i];
                      final snoozeMs  = s.id != null ? _snoozeUntil[s.id] : null;
                      final isSkipped = s.id != null && _skippedIds.contains(s.id);

                      return Dismissible(
                        key: ValueKey(s.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.delete_rounded,
                              color: AppTheme.danger),
                        ),
                        confirmDismiss: (_) async {
                          await _delete(s);
                          return false;
                        },
                        child: _ScheduleTile(
                          schedule:    s,
                          snoozeUntil: snoozeMs,
                          isSkipped:   isSkipped,
                          onToggle:    (v) => _toggle(s, v),
                          onTap:       () => _openBuilder(existing: s),
                          onEdit:      () => _openBuilder(existing: s),
                          onDelete:    () => _delete(s),
                          onSnooze:    (m) => _snooze(s, m),
                          onSkip:      () => _skip(s),
                          onClearSnooze: () => _clearSnooze(s),
                          onClearSkip:   () => _clearSkip(s),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ── Schedule tile ─────────────────────────────────────────────
class _ScheduleTile extends StatelessWidget {
  final ScheduleModel          schedule;
  final int?                   snoozeUntil; // epoch ms, null = not snoozed
  final bool                   isSkipped;
  final ValueChanged<bool>     onToggle;
  final VoidCallback           onTap;
  final VoidCallback           onEdit;
  final VoidCallback           onDelete;
  final Future<void> Function(int)  onSnooze;
  final Future<void> Function()     onSkip;
  final Future<void> Function()     onClearSnooze;
  final Future<void> Function()     onClearSkip;

  const _ScheduleTile({
    required this.schedule,
    required this.snoozeUntil,
    required this.isSkipped,
    required this.onToggle,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onSnooze,
    required this.onSkip,
    required this.onClearSnooze,
    required this.onClearSkip,
  });

  String _fmtTime() {
    final h    = schedule.triggerTime.hour;
    final m    = schedule.triggerTime.minute.toString().padLeft(2, '0');
    final h12  = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    final ampm = h >= 12 ? 'PM' : 'AM';
    return '$h12:$m $ampm';
  }

  String _fmtDays() {
    if (schedule.daysOfWeek.length == 7) return 'Every day';
    if (schedule.daysOfWeek.toSet().containsAll({1, 2, 3, 4, 5}) &&
        !schedule.daysOfWeek.contains(6) &&
        !schedule.daysOfWeek.contains(7)) {
      return 'Weekdays';
    }
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return schedule.daysOfWeek.map((d) => names[d - 1]).join(' · ');
  }

  // Human-readable snooze label e.g. "+20 min" or "until 11:30 PM"
  String _snoozeLabel() {
    if (snoozeUntil == null) return '';
    final until  = DateTime.fromMillisecondsSinceEpoch(snoozeUntil!);
    final now    = DateTime.now();
    final diff   = until.difference(now);
    final mins   = diff.inMinutes;
    if (mins <= 0) return '';
    if (mins < 60) return '+$mins min';
    final h   = until.hour;
    final m   = until.minute.toString().padLeft(2, '0');
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    final ap  = h >= 12 ? 'PM' : 'AM';
    return 'until $h12:$m $ap';
  }

  _BundleStyle _style() {
    final a = schedule.actions.toSet();
    if (a.contains(AppConstants.actionStopMedia) &&
        a.contains(AppConstants.actionDimBrightness) &&
        a.contains(AppConstants.actionDoNotDisturb)) {
      return const _BundleStyle(Icons.nightlight_round, Color(0xFF60A5FA), 'Sleep mode');
    }
    if (a.contains(AppConstants.actionGoHome) &&
        a.contains(AppConstants.actionDoNotDisturb) &&
        !a.contains(AppConstants.actionStopMedia)) {
      return const _BundleStyle(Icons.center_focus_strong_rounded,
          Color(0xFFFBBF24), 'Focus time');
    }
    if (a.contains(AppConstants.actionDoNotDisturb) && a.length == 1) {
      return const _BundleStyle(Icons.do_not_disturb_rounded,
          Color(0xFFA78BFA), 'Silent hours');
    }
    if (a.contains(AppConstants.actionDimBrightness) &&
        !a.contains(AppConstants.actionDoNotDisturb)) {
      return const _BundleStyle(Icons.battery_saver_rounded,
          Color(0xFF34D399), 'Battery saver');
    }
    if (a.contains(AppConstants.actionStopMedia) && a.length <= 2) {
      return const _BundleStyle(Icons.music_off_rounded,
          Color(0xFFF472B6), 'Stop media');
    }
    return _BundleStyle(Icons.tune_rounded, AppTheme.accentLight, schedule.name);
  }

  @override
  Widget build(BuildContext context) {
    final style      = _style();
    final snoozeText = _snoozeLabel();
    final showSnooze = snoozeText.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showQuickActions(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSkipped
              ? AppTheme.surface.withValues(alpha: 0.6)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSkipped
                ? AppTheme.warning.withValues(alpha: 0.35)
                : showSnooze
                    ? AppTheme.accentLight.withValues(alpha: 0.35)
                    : schedule.enabled
                        ? AppTheme.border2
                        : AppTheme.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [

              // Bundle icon
              Container(width: 40, height: 40,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: isSkipped ? 0.06 : 0.12),
                  borderRadius: BorderRadius.circular(11)),
                child: Icon(style.icon,
                    color: style.color.withValues(alpha: isSkipped ? 0.45 : 1.0),
                    size: 20)),
              const SizedBox(width: 12),

              // Info
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(schedule.name,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: (schedule.enabled && !isSkipped)
                            ? AppTheme.textPrimary : AppTheme.textSecond)),
                const SizedBox(height: 2),
                Text('${_fmtTime()} · ${_fmtDays()}',
                    style: const TextStyle(fontSize: 10, color: AppTheme.textHint)),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4)),
                  child: Text(style.label,
                    style: TextStyle(fontSize: 9, color: style.color,
                        fontWeight: FontWeight.w600)),
                ),
              ])),

              // Toggle
              Switch(value: schedule.enabled && !isSkipped,
                  onChanged: isSkipped ? null : onToggle,
                  activeThumbColor: style.color),
              const SizedBox(width: 4),

              // Three-dot menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 18,
                    color: AppTheme.textHint),
                color: AppTheme.surface2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onSelected: (v) async {
                  switch (v) {
                    case 'edit':         onEdit(); break;
                    case 'snooze':       _showQuickActions(context); break;
                    case 'skip':         onSkip(); break;
                    case 'clear_snooze': onClearSnooze(); break;
                    case 'clear_skip':   onClearSkip(); break;
                    case 'delete':       onDelete(); break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit',
                    child: _MenuRow(Icons.edit_rounded, 'Edit schedule',
                        AppTheme.textPrimary)),
                  if (!showSnooze)
                    const PopupMenuItem(value: 'snooze',
                      child: _MenuRow(Icons.snooze_rounded, 'Snooze tonight',
                          AppTheme.accentLight))
                  else
                    const PopupMenuItem(value: 'clear_snooze',
                      child: _MenuRow(Icons.alarm_off_rounded, 'Clear snooze',
                          AppTheme.accentLight)),
                  if (!isSkipped)
                    const PopupMenuItem(value: 'skip',
                      child: _MenuRow(Icons.skip_next_rounded, 'Skip today',
                          AppTheme.textSecond))
                  else
                    const PopupMenuItem(value: 'clear_skip',
                      child: _MenuRow(Icons.replay_rounded, 'Un-skip today',
                          AppTheme.textSecond)),
                  const PopupMenuItem(value: 'delete',
                    child: _MenuRow(Icons.delete_rounded, 'Delete',
                        AppTheme.danger)),
                ],
              ),
            ]),

            // ── Status badges row ─────────────────────────────
            if (showSnooze || isSkipped) ...[
              const SizedBox(height: 10),
              Row(children: [
                const SizedBox(width: 52), // align under text
                if (showSnooze)
                  _StatusBadge(
                    icon:  Icons.snooze_rounded,
                    label: 'Snoozed $snoozeText',
                    color: AppTheme.accentLight,
                    onClear: onClearSnooze,
                  ),
                if (showSnooze && isSkipped)
                  const SizedBox(width: 6),
                if (isSkipped)
                  _StatusBadge(
                    icon:  Icons.skip_next_rounded,
                    label: 'Skipped today',
                    color: AppTheme.warning,
                    onClear: onClearSkip,
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  void _showQuickActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppTheme.textHint,
                borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text(schedule.name, style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          Text('${_fmtTime()} · ${_fmtDays()}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecond)),
          const SizedBox(height: 20),
          const Align(alignment: Alignment.centerLeft,
            child: Text('SNOOZE TONIGHT',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                  color: AppTheme.textHint, letterSpacing: 1.2))),
          const SizedBox(height: 8),
          Row(children: [15, 30, 60].map((m) => Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OutlinedButton(
                onPressed: () { Navigator.pop(context); onSnooze(m); },
                style: OutlinedButton.styleFrom(side: BorderSide(
                    color: AppTheme.accentLight.withValues(alpha: 0.4))),
                child: Text('+$m min',
                    style: const TextStyle(
                        color: AppTheme.accentLight, fontSize: 12)),
              ),
            ),
          )).toList()),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () { Navigator.pop(context); onSkip(); },
              icon: const Icon(Icons.skip_next_rounded,
                  size: 16, color: AppTheme.textSecond),
              label: const Text('Skip today',
                  style: TextStyle(color: AppTheme.textSecond)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.border)),
            )),
        ]),
      ),
    );
  }
}

// ── Status badge with ×-clear button ─────────────────────────
class _StatusBadge extends StatelessWidget {
  final IconData             icon;
  final String               label;
  final Color                color;
  final Future<void> Function() onClear;

  const _StatusBadge({
    required this.icon,
    required this.label,
    required this.color,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 4, 3),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 10, color: color,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onClear,
          child: Icon(Icons.close_rounded, size: 11,
              color: color.withValues(alpha: 0.65)),
        ),
      ]),
    );
  }
}

class _BundleStyle {
  final IconData icon; final Color color; final String label;
  const _BundleStyle(this.icon, this.color, this.label);
}

class _MenuRow extends StatelessWidget {
  final IconData icon; final String label; final Color color;
  const _MenuRow(this.icon, this.label, this.color);
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 16, color: color),
    const SizedBox(width: 10),
    Text(label, style: TextStyle(fontSize: 13, color: color)),
  ]);
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 80, height: 80,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24)),
          child: const Icon(Icons.schedule_rounded,
              size: 38, color: AppTheme.textHint)),
        const SizedBox(height: 20),
        const Text('No schedules yet',
            style: TextStyle(fontSize: 17,
                fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        const Text('Set up your first sleep schedule',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecond)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Create schedule'),
        ),
      ]),
    );
  }
}