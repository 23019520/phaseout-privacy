// ─────────────────────────────────────────────────────────────
//  lib/widgets/day_selector.dart
//  PhaseOut — Day of week multi-select pill row
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../utils/constants.dart';

class DaySelector extends StatelessWidget {

  final List<int>          selectedDays;
  final ValueChanged<List<int>> onChanged;

  const DaySelector({
    super.key,
    required this.selectedDays,
    required this.onChanged,
  });

  void _toggleDay(int weekday) {
    final updated = List<int>.from(selectedDays);
    if (updated.contains(weekday)) {
      updated.remove(weekday);
    } else {
      updated.add(weekday);
    }
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final weekday  = i + 1; // 1=Mon … 7=Sun
        final selected = selectedDays.contains(weekday);
        return GestureDetector(
          onTap: () => _toggleDay(weekday),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width:  40,
            height: 40,
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.accent
                  : AppTheme.surface2,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? AppTheme.accent
                    : const Color(0xFF1F3A5F),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                AppConstants.dayLetters[i],
                style: TextStyle(
                  fontSize:   13,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : AppTheme.textSecond,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}