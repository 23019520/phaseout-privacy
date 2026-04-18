// ─────────────────────────────────────────────────────────────
//  lib/widgets/action_chip_row.dart
//  PhaseOut — Selectable action chips for schedule builder
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../utils/constants.dart';

class ActionChipRow extends StatelessWidget {

  final List<String>                selectedActions;
  final ValueChanged<List<String>>  onChanged;

  const ActionChipRow({
    super.key,
    required this.selectedActions,
    required this.onChanged,
  });

  static const _actions = [
    _ActionDef(
      value: AppConstants.actionStopMedia,
      label: 'Stop media',
      icon:  Icons.stop_circle_rounded,
    ),
    _ActionDef(
      value: AppConstants.actionSendNotification,
      label: 'Notify me',
      icon:  Icons.notifications_rounded,
    ),
    _ActionDef(
      value: AppConstants.actionLaunchApp,
      label: 'Launch app',
      icon:  Icons.launch_rounded,
    ),
  ];

  void _toggle(String action) {
    final updated = List<String>.from(selectedActions);
    if (updated.contains(action)) {
      updated.remove(action);
    } else {
      updated.add(action);
    }
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _actions.map((def) {
        final selected = selectedActions.contains(def.value);
        return GestureDetector(
          onTap: () => _toggle(def.value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.accent.withValues(alpha: 0.12)
                  : AppTheme.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? AppTheme.accent
                    : const Color(0xFF1F3A5F),
                width: selected ? 1.5 : 0.5,
              ),
            ),
            child: Row(children: [
              Icon(def.icon,
                color: selected ? AppTheme.accentLight : AppTheme.textSecond,
                size: 20),
              const SizedBox(width: 12),
              Text(def.label,
                style: TextStyle(
                  fontSize:   14,
                  fontWeight: FontWeight.w500,
                  color: selected
                      ? AppTheme.textPrimary
                      : AppTheme.textSecond,
                )),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width:  20,
                height: 20,
                decoration: BoxDecoration(
                  color: selected ? AppTheme.accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? AppTheme.accent
                        : AppTheme.textHint,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

class _ActionDef {
  final String   value;
  final String   label;
  final IconData icon;
  const _ActionDef({
    required this.value,
    required this.label,
    required this.icon,
  });
}