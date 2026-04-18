// ─────────────────────────────────────────────────────────────
//  lib/screens/schedule_builder_screen.dart  — v5
//
//  BUG FIX — why alarm wasn't saving:
//  The ScheduleModel constructor requires `wakeTime` as a named
//  param. Previously the DB insert was called before the model
//  was fully built in some code paths. Now we build the model
//  FIRST, verify it, then insert. Also: the model was not
//  passing wakeTime through copyWith on edits — fixed.
//
//  UI: advanced options behind an expander to reduce clutter.
//  Contextual permissions: DND and brightness show a snackbar
//  guiding the user to grant when they enable the toggle.
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../db/database_helper.dart';
import '../models/schedule_model.dart';
import '../utils/constants.dart';
import '../widgets/action_chip_row.dart';
import '../widgets/day_selector.dart';
import '../widgets/time_picker_field.dart';
import 'dashboard_screen.dart';

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
  TimeOfDay?   _time;
  List<int>    _days    = [];
  List<String> _actions = [
    AppConstants.actionStopMedia,
    AppConstants.actionSendNotification,
  ];

  // Bedtime extras
  bool      _goHome          = false;
  bool      _doNotDisturb    = false;
  bool      _dimBrightness   = false;
  bool      _setMorningAlarm = false;
  TimeOfDay _wakeTime        = const TimeOfDay(hour: 7, minute: 0);

  bool _showAdvanced = false;
  bool _saving       = false;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    if (s != null) {
      _nameCtrl.text   = s.name;
      _time            = s.triggerTime;
      _days            = List.from(s.daysOfWeek);
      _actions         = List.from(s.actions);
      _goHome          = s.actions.contains(AppConstants.actionGoHome);
      _doNotDisturb    = s.actions.contains(AppConstants.actionDoNotDisturb);
      _dimBrightness   = s.actions.contains(AppConstants.actionDimBrightness);
      _setMorningAlarm = s.wakeTime != null;
      // FIX: always read wakeTime from existing model
      if (s.wakeTime != null) _wakeTime = s.wakeTime!;
      // Auto-expand advanced if any extra is set
      if (_goHome || _doNotDisturb || _dimBrightness || _setMorningAlarm) {
        _showAdvanced = true;
      }
    }
  }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  // ── Contextual permission guidance ────────────────────────
  void _onDndToggle(bool value) {
    setState(() => _doNotDisturb = value);
    if (value) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(seconds: 5),
        content: Text(
          'To use Do Not Disturb: Settings → Apps → Special access → Do Not Disturb → PhaseOut → Allow'),
      ));
    }
  }

  void _onBrightnessToggle(bool value) {
    setState(() => _dimBrightness = value);
    if (value) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(seconds: 5),
        content: Text(
          'To dim brightness: Settings → Apps → Special access → Modify system settings → PhaseOut → Allow'),
      ));
    }
  }

  // ── Save ──────────────────────────────────────────────────
  Future<void> _save() async {
    if (_time == null) { _err('Please set a bedtime.'); return; }
    if (_days.isEmpty) { _err('Please choose at least one day.'); return; }

    // Build the full action list
    final actions = List<String>.from(_actions);
    void sync(bool on, String key) {
      if (on && !actions.contains(key)) actions.add(key);
      if (!on) actions.remove(key);
    }
    sync(_goHome,          AppConstants.actionGoHome);
    sync(_doNotDisturb,    AppConstants.actionDoNotDisturb);
    sync(_dimBrightness,   AppConstants.actionDimBrightness);
    sync(_setMorningAlarm, AppConstants.actionSetMorningAlarm);

    final name = _nameCtrl.text.trim().isEmpty
        ? 'Bedtime' : _nameCtrl.text.trim();

    // FIX: Build model completely BEFORE saving.
    // wakeTime is only set when the toggle is on AND a time has
    // been chosen. Defaulting to 7:00 AM if toggle is on.
    final wakeTimeToSave = _setMorningAlarm ? _wakeTime : null;

    final model = ScheduleModel(
      id:          widget.existing?.id,
      name:        name,
      triggerTime: _time!,
      daysOfWeek:  _days,
      actions:     actions,
      enabled:     true,
      createdAt:   widget.existing?.createdAt ?? DateTime.now(),
      wakeTime:    wakeTimeToSave,  // explicitly assigned
    );

    // Verify model looks correct before hitting DB
    assert(
      _setMorningAlarm ? model.wakeTime != null : model.wakeTime == null,
      'wakeTime mismatch in model',
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
          (_) => false,
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _err('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _err(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
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
            const Padding(padding: EdgeInsets.all(16),
              child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)))
          else
            TextButton(
              onPressed: _save,
              child: Text(widget.isFirstTime ? 'Done' : 'Save',
                style: const TextStyle(
                    color:      AppTheme.accentLight,
                    fontWeight: FontWeight.w600,
                    fontSize:   14)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [

          // First-time hint
          if (widget.isFirstTime) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.accentLight.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.accentLight.withValues(alpha: 0.2))),
              child: Row(children: [
                const Icon(Icons.nightlight_round,
                    color: AppTheme.accentLight, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Set your bedtime once — PhaseOut handles the rest every night.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.accentLight.withValues(alpha: 0.85),
                      height: 1.5,
                    )),
                ),
              ]),
            ),
            const SizedBox(height: 20),
          ],

          // Name
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText:  'Schedule name',
              hintText:   'e.g. Bedtime',
              prefixIcon: Icon(Icons.label_rounded,
                  color: AppTheme.textSecond, size: 18),
            ),
          ),
          const SizedBox(height: 24),

          // Bedtime
          const _Label('Bedtime'),
          const SizedBox(height: 10),
          TimePickerField(
            selectedTime: _time,
            onChanged:    (t) => setState(() => _time = t),
            label:        'Tap to set bedtime',
          ),
          const SizedBox(height: 24),

          // Repeat
          const _Label('Repeat on'),
          const SizedBox(height: 10),
          DaySelector(
            selectedDays: _days,
            onChanged:    (d) => setState(() => _days = d),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, children: [
            _Pill('Every day',
                () => setState(() => _days = [1, 2, 3, 4, 5, 6, 7])),
            _Pill('Weekdays',
                () => setState(() => _days = [1, 2, 3, 4, 5])),
            _Pill('Weekends',
                () => setState(() => _days = [6, 7])),
          ]),
          const SizedBox(height: 24),

          // Actions
          const _Label('Actions'),
          const SizedBox(height: 10),
          ActionChipRow(
            selectedActions: _actions,
            onChanged: (a) => setState(() => _actions = a),
          ),
          const SizedBox(height: 24),

          // Advanced options expander
          GestureDetector(
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(children: [
                const Icon(Icons.tune_rounded,
                    size: 16, color: AppTheme.textSecond),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Advanced options',
                    style: TextStyle(
                        fontSize:   13,
                        fontWeight: FontWeight.w500,
                        color:      AppTheme.textPrimary)),
                ),
                // Summary when collapsed
                if (!_showAdvanced) ...[
                  if (_goHome || _doNotDisturb ||
                      _dimBrightness || _setMorningAlarm) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        [
                          if (_goHome)          'Home',
                          if (_doNotDisturb)    'DND',
                          if (_dimBrightness)   'Dim',
                          if (_setMorningAlarm) 'Alarm',
                        ].join(' · '),
                        style: const TextStyle(
                            fontSize:   10,
                            color:      AppTheme.accentLight,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
                Icon(
                  _showAdvanced
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size:  18,
                  color: AppTheme.textHint,
                ),
              ]),
            ),
          ),

          if (_showAdvanced) ...[
            const SizedBox(height: 12),

            _ToggleRow(
              icon:      Icons.home_rounded,
              color:     AppTheme.tealLight,
              title:     'Go to home screen',
              sub:       'Pauses TikTok, Reels and video apps',
              value:     _goHome,
              onChanged: (v) => setState(() => _goHome = v),
            ),
            _ToggleRow(
              icon:      Icons.do_not_disturb_rounded,
              color:     AppTheme.amber,
              title:     'Do Not Disturb',
              sub:       'Silences calls and notifications until morning',
              value:     _doNotDisturb,
              onChanged: _onDndToggle,
            ),
            _ToggleRow(
              icon:      Icons.brightness_2_rounded,
              color:     const Color(0xFFA78BFA),
              title:     'Dim brightness',
              sub:       'Reduces screen to minimum brightness',
              value:     _dimBrightness,
              onChanged: _onBrightnessToggle,
            ),

            const Divider(color: AppTheme.border, height: 24),

            // Morning alarm toggle
            _ToggleRow(
              icon:      Icons.alarm_rounded,
              color:     const Color(0xFFFBBF24),
              title:     'Morning alarm',
              sub:       'Restores brightness & DND at your wake time',
              value:     _setMorningAlarm,
              onChanged: (v) => setState(() => _setMorningAlarm = v),
            ),

            // Wake time picker — shows when toggle is on
            if (_setMorningAlarm) ...[
              const SizedBox(height: 12),
              TimePickerField(
                selectedTime: _wakeTime,
                onChanged: (t) => setState(() =>
                    _wakeTime =
                        t ?? const TimeOfDay(hour: 7, minute: 0)),
                label: 'Wake time',
              ),
              const SizedBox(height: 6),
              const Text(
                'PhaseOut will set an alarm and restore your '
                'brightness and DND settings at this time.',
                style: TextStyle(
                    fontSize: 11,
                    color:    AppTheme.textHint,
                    height:   1.5),
              ),
            ],
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 16)),
              child: Text(
                widget.isFirstTime
                    ? 'Save bedtime & start'
                    : (widget.existing == null
                        ? 'Create schedule'
                        : 'Save changes'),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          if (widget.isFirstTime) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (_) => const DashboardScreen()),
                  (_) => false,
                ),
                child: const Text('Skip for now',
                  style: TextStyle(
                      fontSize: 13, color: AppTheme.textHint)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final IconData           icon;
  final Color              color;
  final String             title, sub;
  final bool               value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.icon, required this.color,
      required this.title, required this.sub,
      required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: value
              ? color.withValues(alpha: 0.06)
              : AppTheme.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: value
                  ? color.withValues(alpha: 0.25)
                  : AppTheme.border),
        ),
        child: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color:        color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(title,
              style: const TextStyle(
                  fontSize:   13,
                  fontWeight: FontWeight.w500,
                  color:      AppTheme.textPrimary)),
            const SizedBox(height: 2),
            Text(sub,
              style: const TextStyle(
                  fontSize: 10,
                  color:    AppTheme.textSecond,
                  height:   1.4)),
          ])),
          const SizedBox(width: 6),
          Switch(value: value, onChanged: onChanged),
        ]),
      );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
            fontSize:      10,
            fontWeight:    FontWeight.w600,
            color:         AppTheme.textHint,
            letterSpacing: 1.2),
      );
}

class _Pill extends StatelessWidget {
  final String label; final VoidCallback onTap;
  const _Pill(this.label, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color:        AppTheme.surface2,
            borderRadius: BorderRadius.circular(99),
            border:       Border.all(color: AppTheme.border),
          ),
          child: Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppTheme.textSecond)),
        ),
      );
}