// ─────────────────────────────────────────────────────────────
//  lib/widgets/schedule_card.dart
//  PhaseOut — Schedule list item card
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/schedule_model.dart';
import '../utils/time_utils.dart';

class ScheduleCard extends StatelessWidget {

  final ScheduleModel   schedule;
  final ValueChanged<bool> onToggle;
  final VoidCallback    onTap;
  final VoidCallback?   onDelete;

  const ScheduleCard({
    super.key,
    required this.schedule,
    required this.onToggle,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final next = TimeUtils.nextOccurrence(schedule);
    final rel  = TimeUtils.relativeOccurrence(next);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: schedule.enabled
              ? AppTheme.surface2
              : AppTheme.surface2.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: schedule.enabled
                ? const Color(0xFF1F3A5F)
                : const Color(0xFF1A2A3A),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Row(children: [
              Expanded(
                child: Text(
                  schedule.name,
                  style: TextStyle(
                    fontSize:   15,
                    fontWeight: FontWeight.w600,
                    color: schedule.enabled
                        ? AppTheme.textPrimary
                        : AppTheme.textSecond,
                  ),
                ),
              ),
              Switch(
                value:    schedule.enabled,
                onChanged: onToggle,
              ),
            ]),

            const SizedBox(height: 4),

            // Time
            Text(
              schedule.formattedTime,
              style: TextStyle(
                fontSize:   26,
                fontWeight: FontWeight.w700,
                color: schedule.enabled
                    ? AppTheme.accentLight
                    : AppTheme.textHint,
              ),
            ),

            const SizedBox(height: 8),

            Row(children: [
              // Days
              Expanded(
                child: Text(
                  schedule.formattedDays,
                  style: const TextStyle(
                    fontSize: 12,
                    color:    AppTheme.textSecond,
                  ),
                ),
              ),
              // Next occurrence
              if (schedule.enabled)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:        AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'Next: $rel',
                    style: const TextStyle(
                      fontSize: 11,
                      color:    AppTheme.accentLight,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}