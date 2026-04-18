// ─────────────────────────────────────────────────────────────
//  lib/services/scheduler_service.dart
//  PhaseOut — Flutter scheduler (UI sync only)
//
//  PhaseOutService (Kotlin) now owns schedule evaluation,
//  media stop, pre-notifications, and focus detection.
//
//  This class handles only what needs Flutter:
//    • Usage stats sync to DB (for usage screen display)
//    • Battery snapshot recording
//    • Audio timer UI state check
// ─────────────────────────────────────────────────────────────

import '../utils/logger.dart';
import 'usage_monitor_service.dart';
import 'battery_service.dart';

class SchedulerService {

  static const String _tag = 'SchedulerService';
  SchedulerService._();

  // Called by Flutter BGS tick (60s) for Flutter-side sync.
  // Native scheduling is handled by PhaseOutService (Kotlin).
  static Future<void> evaluate() async {
    AppLogger.bg(_tag, 'Flutter sync tick');

    // Sync usage stats to DB so usage screen stays current
    await UsageMonitorService.checkLimits();

    // Record battery snapshot for ML prediction
    await BatteryService.recordSnapshot();
  }
}