// ─────────────────────────────────────────────────────────────
//  lib/widgets/battery_tile.dart
//  PhaseOut — Battery status tile with ML discharge prediction
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import '../app_theme.dart';
import '../services/battery_prediction_service.dart';

class BatteryTile extends StatefulWidget {
  const BatteryTile({super.key});

  @override
  State<BatteryTile> createState() => _BatteryTileState();
}

class _BatteryTileState extends State<BatteryTile> {

  final Battery _battery = Battery();

  int     _level      = 0;
  bool    _charging   = false;
  String? _prediction; // e.g. "~11:30 PM" or null if insufficient data
  String? _rateString; // e.g. "3.2%/hr"
  Timer?  _timer;
  StreamSubscription<BatteryState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _refresh();

    // Listen for charging state changes — update immediately
    _stateSub = _battery.onBatteryStateChanged.listen((_) => _refresh());

    // Poll every 5 minutes as a fallback
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final level  = await _battery.batteryLevel;
      final state  = await _battery.batteryState;
      final pred   = await BatteryPredictionService.predictLowBatteryTime();
      final rate   = await BatteryPredictionService.averageDischargeRate();

      if (mounted) {
        setState(() {
          _level      = level;
          _charging   = state == BatteryState.charging ||
                        state == BatteryState.full;
          _prediction = pred;
          _rateString = rate;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  Color get _levelColor {
    if (_charging)   return AppTheme.tealLight;
    if (_level < 20) return AppTheme.danger;
    if (_level < 50) return AppTheme.warning;
    return AppTheme.success;
  }

  IconData get _icon {
    if (_charging)   return Icons.battery_charging_full_rounded;
    if (_level < 20) return Icons.battery_alert_rounded;
    if (_level < 50) return Icons.battery_3_bar_rounded;
    return Icons.battery_full_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _refresh,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        AppTheme.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFF1F3A5F), width: 0.5),
        ),
        child: Row(
          children: [
            // Battery icon
            Icon(_icon, color: _levelColor, size: 32),
            const SizedBox(width: 14),

            // Level + status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(
                      '$_level%',
                      style: TextStyle(
                        fontSize:   24,
                        fontWeight: FontWeight.w700,
                        color:      _levelColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _charging ? '· Charging' : '· Discharging',
                      style: const TextStyle(
                        fontSize: 12,
                        color:    AppTheme.textSecond,
                      ),
                    ),
                  ]),

                  // Prediction line — only shows if we have data
                  if (_prediction != null && !_charging) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.schedule_rounded,
                          size: 11, color: AppTheme.textHint),
                      const SizedBox(width: 4),
                      Text(
                        'Low battery $_prediction',
                        style: const TextStyle(
                          fontSize: 11,
                          color:    AppTheme.textHint,
                        ),
                      ),
                      if (_rateString != null) ...[
                        const Text('  ·  ',
                          style: TextStyle(
                            fontSize: 11,
                            color:    AppTheme.textHint,
                          )),
                        Text(
                          _rateString!,
                          style: const TextStyle(
                            fontSize: 11,
                            color:    AppTheme.textHint,
                          ),
                        ),
                      ],
                    ]),
                  ],

                  // Charging — no prediction needed
                  if (_charging) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Prediction paused while charging',
                      style: TextStyle(
                        fontSize: 11,
                        color:    AppTheme.textHint,
                      ),
                    ),
                  ],

                  // Not enough data yet
                  if (_prediction == null && !_charging) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Prediction available after 24 h of data',
                      style: TextStyle(
                        fontSize: 11,
                        color:    AppTheme.textHint,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Tap to refresh hint
            const Icon(Icons.refresh_rounded,
                size: 14, color: AppTheme.textHint),
          ],
        ),
      ),
    );
  }
}