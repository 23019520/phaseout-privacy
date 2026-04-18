// ─────────────────────────────────────────────────────────────
//  lib/screens/scenario_screen.dart
//  PhaseOut — Scenario engine (v1.1 placeholder)
//
//  ROOT CAUSE FIX: The old version declared `class SchedulesScreen`
//  which conflicted with schedules_screen.dart. That single
//  duplicate class name caused 249 cascade errors across the
//  entire project (Text, ScheduleBuilderScreen all ambiguous).
//
//  This file now declares ScenarioScreen only.
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../app_theme.dart';

class ScenarioScreen extends StatelessWidget {
  const ScenarioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  size: 34, color: AppTheme.textHint),
            ),
            const SizedBox(height: 20),
            const Text('Scenarios',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            const Text('Coming in v1.1',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecond)),
          ],
        ),
      ),
    );
  }
}