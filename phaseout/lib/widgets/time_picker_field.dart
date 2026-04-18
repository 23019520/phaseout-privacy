// ─────────────────────────────────────────────────────────────
//  lib/widgets/time_picker_field.dart
//  PhaseOut — Tappable time display that opens time picker
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../utils/time_utils.dart';

class TimePickerField extends StatelessWidget {

  final TimeOfDay?                  selectedTime;
  final ValueChanged<TimeOfDay>     onChanged;
  final String                      label;

  const TimePickerField({
    super.key,
    required this.selectedTime,
    required this.onChanged,
    this.label = 'Time',
  });

  Future<void> _pick(BuildContext context) async {
    final picked = await showTimePicker(
      context:     context,
      initialTime: selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: const TimePickerThemeData(
              backgroundColor: AppTheme.surface,
              hourMinuteColor: AppTheme.surface2,
              dialBackgroundColor: AppTheme.surface2,
              hourMinuteTextColor: AppTheme.textPrimary,
              dialHandColor: AppTheme.accent,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _pick(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color:        AppTheme.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1F3A5F), width: 0.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time_rounded,
                color: AppTheme.textSecond, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                  style: const TextStyle(
                    fontSize: 11,
                    color:    AppTheme.textHint,
                  )),
                const SizedBox(height: 2),
                Text(
                  selectedTime != null
                      ? TimeUtils.formatTimeOfDay(selectedTime!)
                      : 'Tap to set time',
                  style: TextStyle(
                    fontSize:   18,
                    fontWeight: FontWeight.w700,
                    color: selectedTime != null
                        ? AppTheme.textPrimary
                        : AppTheme.textHint,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: AppTheme.textHint),
          ],
        ),
      ),
    );
  }
}