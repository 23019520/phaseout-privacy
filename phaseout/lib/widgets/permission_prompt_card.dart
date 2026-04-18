// ─────────────────────────────────────────────────────────────
//  lib/widgets/permission_prompt_card.dart
//  PhaseOut — Permission status card with grant button
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../app_theme.dart';

class PermissionPromptCard extends StatelessWidget {

  final String       title;
  final String       description;
  final bool         granted;
  final bool         required;
  final VoidCallback onGrant;
  final IconData     icon;

  const PermissionPromptCard({
    super.key,
    required this.title,
    required this.description,
    required this.granted,
    required this.onGrant,
    this.required = true,
    this.icon = Icons.security_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: granted
            ? AppTheme.success.withValues(alpha: 0.06)
            : AppTheme.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: granted
              ? AppTheme.success.withValues(alpha: 0.3)
              : const Color(0xFF1F3A5F),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: granted
                  ? AppTheme.success.withValues(alpha: 0.12)
                  : AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              granted ? Icons.check_circle_rounded : icon,
              color:  granted ? AppTheme.success : AppTheme.accent,
              size:   20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(title,
                    style: const TextStyle(
                      fontSize:   13,
                      fontWeight: FontWeight.w600,
                      color:      AppTheme.textPrimary,
                    )),
                  const SizedBox(width: 6),
                  if (required)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color:        AppTheme.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Required',
                        style: TextStyle(
                          fontSize:   9,
                          color:      AppTheme.danger,
                          fontWeight: FontWeight.w600,
                        )),
                    ),
                ]),
                const SizedBox(height: 2),
                Text(description,
                  style: const TextStyle(
                    fontSize: 11,
                    color:    AppTheme.textHint,
                  )),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (granted)
            const Icon(Icons.check_rounded,
                color: AppTheme.success, size: 20)
          else
            TextButton(
              onPressed: onGrant,
              style: TextButton.styleFrom(
                backgroundColor: AppTheme.accent.withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Grant',
                style: TextStyle(
                  fontSize:   12,
                  color:      AppTheme.accentLight,
                  fontWeight: FontWeight.w600,
                )),
            ),
        ],
      ),
    );
  }
}