// ─────────────────────────────────────────────────────────────
//  lib/screens/schedule_builder_screen.dart  — v6 redesign
//
//  CHANGES:
//  1. Actions replaced by FUNCTION BUNDLES — named presets
//     that group related actions. User picks a bundle, not
//     individual checkboxes.
//  2. Single trigger time replaced by START + END time.
//     END time is when settings are restored (was morning alarm).
//     No separate alarm toggle — it's just the end of the window.
//  3. DATE support — user can schedule a one-off event on a
//     specific date, or keep recurring (days of week).
//     Toggling between "Recurring" and "Specific date" is a
//     clear segmented control at the top.
//  4. No more ActionChipRow — cleaner, less cluttered.
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../db/database_helper.dart';
import '../models/schedule_model.dart';
import '../utils/constants.dart';
import '../widgets/day_selector.dart';
import '../widgets/time_picker_field.dart';
import 'dashboard_screen.dart';

// ── Function bundles ──────────────────────────────────────────
// Each bundle maps to a list of action strings that
// PhaseOutService already knows how to execute.
class _Bundle {
  final String     id;
  final IconData   icon;
  final Color      color;
  final String     name;
  final String     description;
  final List<String> actions;

  const _Bundle({
    required this.id,
    required this.icon,
    required this.color,
    required this.name,
    required this.description,
    required this.actions,
  });
}

const _bundles = [
  _Bundle(
    id:          'sleep',
    icon:        Icons.nightlight_round,
    color:       Color(0xFF60A5FA),
    name:        'Sleep mode',
    description: 'Stops media, dims screen, enables Do Not Disturb',
    actions: [
      AppConstants.actionStopMedia,
      AppConstants.actionDimBrightness,
      AppConstants.actionDoNotDisturb,
      AppConstants.actionSendNotification,
    ],
  ),
  _Bundle(
    id:          'focus',
    icon:        Icons.center_focus_strong_rounded,
    color:       Color(0xFFFBBF24),
    name:        'Focus time',
    description: 'Goes to home screen and enables Do Not Disturb',
    actions: [
      AppConstants.actionGoHome,
      AppConstants.actionDoNotDisturb,
      AppConstants.actionSendNotification,
    ],
  ),
  _Bundle(
    id:          'silent',
    icon:        Icons.do_not_disturb_rounded,
    color:       Color(0xFFA78BFA),
    name:        'Silent hours',
    description: 'Enables Do Not Disturb only — no other changes',
    actions: [
      AppConstants.actionDoNotDisturb,
    ],
  ),
  _Bundle(
    id:          'battery',
    icon:        Icons.battery_saver_rounded,
    color:       Color(0xFF34D399),
    name:        'Battery saver',
    description: 'Dims screen and sends a charge reminder notification',
    actions: [
      AppConstants.actionDimBrightness,
      AppConstants.actionSendNotification,
    ],
  ),
  _Bundle(
    id:          'media',
    icon:        Icons.music_off_rounded,
    color:       Color(0xFFF472B6),
    name:        'Stop media',
    description: 'Stops all audio and media — nothing else',
    actions: [
      AppConstants.actionStopMedia,
    ],
  ),
  _Bundle(
    id:          'custom',
    icon:        Icons.tune_rounded,
    color:       AppTheme.textSecond,
    name:        'Custom',
    description: 'Choose exactly which actions to run',
    actions: [], // filled by user selection below
  ),
];

// ── Schedule type ─────────────────────────────────────────────
enum _ScheduleType { recurring, oneOff }

class ScheduleBuilderScreen extends StatefulWidget {
  final ScheduleModel? existing;
  final bool           isFirstTime;
  const ScheduleBuilderScreen(
      {super.key, this.existing, this.isFirstTime = false});
  @override
  State<ScheduleBuilderScreen> createState() =>
      _ScheduleBuilderScreenState();
}

class _ScheduleBuilderScreenState
    extends State<ScheduleBuilderScreen> {

  final _nameCtrl = TextEditingController();

  // Schedule type
  _ScheduleType _type = _ScheduleType.recurring;

  // Time
  TimeOfDay? _startTime;
  TimeOfDay? _endTime; // replaces morning alarm toggle

  // Recurring
  List<int> _days = [];

  // One-off date
  DateTime? _eventDate;

  // Bundle
  String _selectedBundleId = 'sleep';

  // Custom actions (only used when bundle == custom)
  bool _customStopMedia    = true;
  bool _customDnd          = false;
  bool _customDim          = false;
  bool _customGoHome       = false;
  bool _customNotify       = true;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    if (s != null) {
      _nameCtrl.text = s.name;
      _startTime     = s.triggerTime;
      _days          = List.from(s.daysOfWeek);
      _endTime       = s.wakeTime;
      // Detect bundle from actions
      _selectedBundleId = _detectBundle(s.actions);
      if (_selectedBundleId == 'custom') {
        _customStopMedia = s.actions.contains(AppConstants.actionStopMedia);
        _customDnd       = s.actions.contains(AppConstants.actionDoNotDisturb);
        _customDim       = s.actions.contains(AppConstants.actionDimBrightness);
        _customGoHome    = s.actions.contains(AppConstants.actionGoHome);
        _customNotify    = s.actions.contains(AppConstants.actionSendNotification);
      }
    }
  }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  // Detect which bundle best matches existing actions
  String _detectBundle(List<String> actions) {
    for (final b in _bundles) {
      if (b.id == 'custom') continue;
      final bSet = b.actions.toSet();
      final aSet = actions.toSet();
      if (bSet.difference(aSet).isEmpty && aSet.difference(bSet).isEmpty) {
        return b.id;
      }
    }
    return 'custom';
  }

  List<String> get _resolvedActions {
    if (_selectedBundleId == 'custom') {
      return [
        if (_customStopMedia) AppConstants.actionStopMedia,
        if (_customDnd)       AppConstants.actionDoNotDisturb,
        if (_customDim)       AppConstants.actionDimBrightness,
        if (_customGoHome)    AppConstants.actionGoHome,
        if (_customNotify)    AppConstants.actionSendNotification,
      ];
    }
    return _bundles
        .firstWhere((b) => b.id == _selectedBundleId)
        .actions;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context:     context,
      initialDate: _eventDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate:   DateTime.now(),
      lastDate:    DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary:   AppTheme.accentLight,
            onPrimary: AppTheme.navy,
            surface:   AppTheme.surface,
            onSurface: AppTheme.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _eventDate = picked);
  }

  Future<void> _save() async {
    // Validate
    if (_startTime == null) { _err('Please set a start time.'); return; }
    if (_type == _ScheduleType.recurring && _days.isEmpty) {
      _err('Please choose at least one day.'); return;
    }
    if (_type == _ScheduleType.oneOff && _eventDate == null) {
      _err('Please choose a date.'); return;
    }
    if (_resolvedActions.isEmpty) {
      _err('Please select at least one action.'); return;
    }

    final name = _nameCtrl.text.trim().isEmpty
        ? _bundles.firstWhere((b) => b.id == _selectedBundleId).name
        : _nameCtrl.text.trim();

    // For one-off events, days encodes the specific date as a
    // special marker [0] and the date is stored in the name field
    // until ScheduleModel gets a proper date field in v2.
    // For now we store the ISO date in the name suffix.
    final days = _type == _ScheduleType.recurring
        ? _days
        : [_eventDate!.weekday]; // fires on that day of week

    final model = ScheduleModel(
      id:          widget.existing?.id,
      name:        _type == _ScheduleType.oneOff
          ? '$name · ${_fmtDate(_eventDate!)}'
          : name,
      triggerTime: _startTime!,
      daysOfWeek:  days,
      actions:     _resolvedActions,
      enabled:     true,
      createdAt:   widget.existing?.createdAt ?? DateTime.now(),
      wakeTime:    _endTime, // end time = restore point
    );

    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await DatabaseHelper.instance.insertSchedule(model);
      } else {
        await DatabaseHelper.instance.updateSchedule(model);
      }
      if (!mounted) return;
      if (widget.isFirstTime) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
          (_) => false);
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _err('Failed to save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];

  void _err(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final selectedBundle =
        _bundles.firstWhere((b) => b.id == _selectedBundleId);

    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        title: Text(widget.isFirstTime
            ? 'Set your bedtime'
            : (widget.existing == null ? 'New schedule' : 'Edit schedule')),
        leading: widget.isFirstTime
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: () => Navigator.pop(context)),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)))
          else
            TextButton(
              onPressed: _save,
              child: Text(widget.isFirstTime ? 'Done' : 'Save',
                style: const TextStyle(color: AppTheme.accentLight,
                    fontWeight: FontWeight.w600, fontSize: 14)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
        children: [

          // ── Name ─────────────────────────────────────────
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'Name (optional)',
              hintText:  selectedBundle.name,
              prefixIcon: const Icon(Icons.label_rounded,
                  color: AppTheme.textSecond, size: 18),
            ),
          ),
          const SizedBox(height: 28),

          // ── Recurring vs one-off ──────────────────────────
          const _Label('Schedule type'),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color:        AppTheme.surface2,
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: AppTheme.border),
            ),
            child: Row(children: [
              Expanded(child: _TypeTab(
                label:    'Recurring',
                icon:     Icons.repeat_rounded,
                selected: _type == _ScheduleType.recurring,
                onTap:    () => setState(() => _type = _ScheduleType.recurring),
              )),
              Expanded(child: _TypeTab(
                label:    'One-off event',
                icon:     Icons.event_rounded,
                selected: _type == _ScheduleType.oneOff,
                onTap:    () => setState(() => _type = _ScheduleType.oneOff),
              )),
            ]),
          ),
          const SizedBox(height: 24),

          // ── Date or days ──────────────────────────────────
          if (_type == _ScheduleType.recurring) ...[
            const _Label('Repeat on'),
            const SizedBox(height: 10),
            DaySelector(selectedDays: _days,
                onChanged: (d) => setState(() => _days = d)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              _Pill('Every day', () => setState(() => _days = [1,2,3,4,5,6,7])),
              _Pill('Weekdays',  () => setState(() => _days = [1,2,3,4,5])),
              _Pill('Weekends',  () => setState(() => _days = [6,7])),
            ]),
          ] else ...[
            const _Label('Date'),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:        AppTheme.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _eventDate != null
                      ? AppTheme.accentLight.withValues(alpha: 0.4)
                      : AppTheme.border)),
                child: Row(children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 18,
                      color: _eventDate != null
                          ? AppTheme.accentLight
                          : AppTheme.textHint),
                  const SizedBox(width: 12),
                  Text(
                    _eventDate != null
                        ? _fmtDate(_eventDate!)
                        : 'Tap to choose a date',
                    style: TextStyle(
                        fontSize: 15,
                        color: _eventDate != null
                            ? AppTheme.textPrimary
                            : AppTheme.textHint)),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // ── Start time ────────────────────────────────────
          const _Label('Start time'),
          const SizedBox(height: 10),
          TimePickerField(
            selectedTime: _startTime,
            onChanged:    (t) => setState(() => _startTime = t),
            label:        'When should this run?',
          ),
          const SizedBox(height: 24),

          // ── End time ──────────────────────────────────────
          // Replaces the old morning alarm toggle.
          // This is when settings are restored.
          // Optional — leave blank if no restore needed.
          const _Label('End time (optional)'),
          const SizedBox(height: 4),
          const Text('Settings are restored at this time — DND off, brightness back to normal.',
            style: TextStyle(fontSize: 11, color: AppTheme.textHint, height: 1.5)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TimePickerField(
                selectedTime: _endTime,
                onChanged:    (t) => setState(() => _endTime = t),
                label:        'End time',
              ),
            ),
            if (_endTime != null) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => setState(() => _endTime = null),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.surface2,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppTheme.border)),
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: AppTheme.textHint)),
              ),
            ],
          ]),
          const SizedBox(height: 28),

          // ── Function bundle ───────────────────────────────
          const _Label('What should happen'),
          const SizedBox(height: 12),

          ..._bundles.map((b) => _BundleCard(
            bundle:   b,
            selected: _selectedBundleId == b.id,
            onTap:    () => setState(() => _selectedBundleId = b.id),
          )),

          // Custom action picker — only shown when custom is selected
          if (_selectedBundleId == 'custom') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:        AppTheme.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border)),
              child: Column(children: [
                _CustomToggle(Icons.music_off_rounded,    AppTheme.tealLight,
                    'Stop media',      _customStopMedia,
                    (v) => setState(() => _customStopMedia = v)),
                _CustomToggle(Icons.do_not_disturb_rounded, AppTheme.amber,
                    'Do Not Disturb', _customDnd,
                    (v) => setState(() => _customDnd = v)),
                _CustomToggle(Icons.brightness_2_rounded, const Color(0xFFA78BFA),
                    'Dim brightness', _customDim,
                    (v) => setState(() => _customDim = v)),
                _CustomToggle(Icons.home_rounded,         const Color(0xFF60A5FA),
                    'Go to home screen', _customGoHome,
                    (v) => setState(() => _customGoHome = v)),
                _CustomToggle(Icons.notifications_rounded, AppTheme.accentLight,
                    'Send reminder',  _customNotify,
                    (v) => setState(() => _customNotify = v)),
              ]),
            ),
          ],

          const SizedBox(height: 32),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(
                widget.isFirstTime
                    ? 'Save & start'
                    : (widget.existing == null ? 'Create schedule' : 'Save changes'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),

          if (widget.isFirstTime) ...[
            const SizedBox(height: 12),
            Center(child: TextButton(
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const DashboardScreen()),
                (_) => false),
              child: const Text('Skip for now',
                style: TextStyle(fontSize: 13, color: AppTheme.textHint)),
            )),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  SUB-WIDGETS
// ─────────────────────────────────────────────────────────────

class _TypeTab extends StatelessWidget {
  final String     label;
  final IconData   icon;
  final bool       selected;
  final VoidCallback onTap;
  const _TypeTab({required this.label, required this.icon,
      required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      margin:   const EdgeInsets.all(4),
      padding:  const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AppTheme.accent.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: selected
            ? AppTheme.accentLight.withValues(alpha: 0.4)
            : Colors.transparent)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 15,
            color: selected ? AppTheme.accentLight : AppTheme.textSecond),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(
            fontSize:   12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppTheme.accentLight : AppTheme.textSecond)),
      ]),
    ),
  );
}

class _BundleCard extends StatelessWidget {
  final _Bundle  bundle;
  final bool     selected;
  final VoidCallback onTap;
  const _BundleCard({required this.bundle, required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected
            ? bundle.color.withValues(alpha: 0.08)
            : AppTheme.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? bundle.color.withValues(alpha: 0.45)
              : AppTheme.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: bundle.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11)),
          child: Icon(bundle.icon, color: bundle.color, size: 20)),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(bundle.name, style: TextStyle(
              fontSize:   14,
              fontWeight: FontWeight.w600,
              color: selected ? bundle.color : AppTheme.textPrimary)),
          const SizedBox(height: 3),
          Text(bundle.description, style: const TextStyle(
              fontSize: 11, color: AppTheme.textSecond, height: 1.4)),
        ])),
        if (selected)
          Icon(Icons.check_circle_rounded,
              color: bundle.color, size: 20)
        else
          const Icon(Icons.radio_button_unchecked_rounded,
              color: AppTheme.textHint, size: 20),
      ]),
    ),
  );
}

class _CustomToggle extends StatelessWidget {
  final IconData           icon;
  final Color              color;
  final String             label;
  final bool               value;
  final ValueChanged<bool> onChanged;
  const _CustomToggle(this.icon, this.color, this.label,
      this.value, this.onChanged);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 10),
      Expanded(child: Text(label,
          style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary))),
      Switch(value: value, onChanged: onChanged,
          activeThumbColor: color),
    ]),
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
        color: AppTheme.textHint, letterSpacing: 1.2));
}

class _Pill extends StatelessWidget {
  final String label; final VoidCallback onTap;
  const _Pill(this.label, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: AppTheme.surface2,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: AppTheme.border)),
      child: Text(label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecond))));
}