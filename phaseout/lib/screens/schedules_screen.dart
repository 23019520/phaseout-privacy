// ─────────────────────────────────────────────────────────────
//  lib/screens/schedules_screen.dart
//  PhaseOut — Schedules list (syncs from DB on every entry)
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../db/database_helper.dart';
import '../models/schedule_model.dart';
import '../services/schedule_action_service.dart';
import 'schedule_builder_screen.dart';

class SchedulesScreen extends StatefulWidget {
  const SchedulesScreen({super.key});
  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen>
    with AutomaticKeepAliveClientMixin {

  List<ScheduleModel> _schedules = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => false; // always reload on tab switch

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sync every time this screen becomes visible
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final schedules = await DatabaseHelper.instance.getAllSchedules();
    if (mounted) setState(() { _schedules = schedules; _loading = false; });
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
                      final s = _schedules[i];
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
                          schedule: s,
                          onToggle: (v) => _toggle(s, v),
                          onTap:    () => _openBuilder(existing: s),
                          onSnooze: (m) => s.id != null
                              ? ScheduleActionService.snooze(s.id!, m)
                              : Future.value(),
                          onSkip:   () => s.id != null
                              ? ScheduleActionService.skipToday(s.id!)
                              : Future.value(),
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
  final ScheduleModel    schedule;
  final ValueChanged<bool> onToggle;
  final VoidCallback       onTap;
  final Future<void> Function(int)  onSnooze;
  final Future<void> Function()     onSkip;

  const _ScheduleTile({
    required this.schedule,
    required this.onToggle,
    required this.onTap,
    required this.onSnooze,
    required this.onSkip,
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
    if (schedule.daysOfWeek.toSet().containsAll({1,2,3,4,5}) &&
        !schedule.daysOfWeek.contains(6) &&
        !schedule.daysOfWeek.contains(7)) {
      return 'Weekdays';
    }
    const names = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return schedule.daysOfWeek.map((d) => names[d-1]).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showQuickActions(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: schedule.enabled
                ? AppTheme.border2 : AppTheme.border),
        ),
        child: Row(children: [

          // Time
          SizedBox(width: 64,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_fmtTime(),
                  style: const TextStyle(fontFamily: 'DMSerifDisplay',
                      fontSize: 20, color: AppTheme.textPrimary, height: 1)),
                if (schedule.hasMorningAlarm)
                  Text('↑ ${schedule.formattedWakeTime}',
                    style: const TextStyle(
                        fontSize: 9, color: AppTheme.textHint)),
              ])),

          Container(width: 1, height: 40,
              color: AppTheme.border,
              margin: const EdgeInsets.symmetric(horizontal: 12)),

          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(schedule.name,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: schedule.enabled
                      ? AppTheme.textPrimary : AppTheme.textSecond)),
              const SizedBox(height: 3),
              Text(_fmtDays(),
                style: const TextStyle(fontSize: 10, color: AppTheme.textHint)),
              const SizedBox(height: 6),
              // Action badges
              Wrap(spacing: 4, children: schedule.actions.map((a) =>
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    _actionLabel(a),
                    style: const TextStyle(
                        fontSize: 9, color: AppTheme.accentLight,
                        fontWeight: FontWeight.w500)),
                )).toList()),
            ])),

          // Toggle
          Switch(value: schedule.enabled, onChanged: onToggle),
        ]),
      ),
    );
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'stop_media':        return 'Stop media';
      case 'send_notification': return 'Notify';
      case 'go_home':           return 'Go home';
      case 'do_not_disturb':    return 'DND';
      case 'dim_brightness':    return 'Dim';
      case 'set_morning_alarm': return 'Alarm';
      default: return action;
    }
  }

  // Long-press quick actions: snooze or skip for today
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
          Text(schedule.name,
            style: const TextStyle(fontSize: 15,
                fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
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
                onPressed: () {
                  Navigator.pop(context);
                  onSnooze(m);
                },
                style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: AppTheme.accentLight.withValues(alpha: 0.4))),
                child: Text('$m min',
                  style: const TextStyle(
                      color: AppTheme.accentLight, fontSize: 12)),
              ),
            ),
          )).toList()),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () { Navigator.pop(context); onSkip(); },
              icon: const Icon(Icons.skip_next_rounded,
                  size: 16, color: AppTheme.textSecond),
              label: const Text('Skip today',
                style: TextStyle(color: AppTheme.textSecond)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.border)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────
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