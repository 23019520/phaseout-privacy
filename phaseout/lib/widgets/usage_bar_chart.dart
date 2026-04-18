// ─────────────────────────────────────────────────────────────
//  lib/widgets/usage_bar_chart.dart
//  PhaseOut — Horizontal bar chart of today's app usage
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/app_usage_model.dart';

class UsageBarChart extends StatelessWidget {

  final List<AppUsageModel> apps;
  final ValueChanged<AppUsageModel>? onTap;

  const UsageBarChart({
    super.key,
    required this.apps,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (apps.isEmpty) {
      return const Center(
        child: Text('No usage data yet',
          style: TextStyle(color: AppTheme.textHint, fontSize: 13)),
      );
    }

    final max = apps.first.usageMinutes;

    return Column(
      children: apps.take(7).map((app) {
        final fraction = max > 0 ? app.usageMinutes / max : 0.0;
        final overLimit = app.isOverLimit;
        final barColor  = overLimit ? AppTheme.danger : AppTheme.accent;
        final label     = app.appLabel.isNotEmpty
            ? app.appLabel
            : app.packageName.split('.').last;

        return GestureDetector(
          onTap: () => onTap?.call(app),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color:    AppTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                      )),
                  ),
                  const SizedBox(width: 8),
                  Text(app.formattedUsage,
                    style: TextStyle(
                      fontSize:   12,
                      color:      overLimit ? AppTheme.danger : AppTheme.textSecond,
                      fontWeight: overLimit ? FontWeight.w600 : FontWeight.w400,
                    )),
                  if (app.limitMinutes != null) ...[
                    Text(' / ${app.formattedLimit}',
                      style: const TextStyle(
                        fontSize: 11,
                        color:    AppTheme.textHint,
                      )),
                  ],
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(children: [
                    Container(
                      height: 6,
                      color:  const Color(0xFF1F3A5F),
                    ),
                    FractionallySizedBox(
                      widthFactor: fraction.clamp(0.0, 1.0),
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    if (app.limitMinutes != null && max > 0)
                      FractionallySizedBox(
                        widthFactor: (app.limitMinutes! / max).clamp(0.0, 1.0),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            width: 2,
                            height: 6,
                            color: AppTheme.warning,
                          ),
                        ),
                      ),
                  ]),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}