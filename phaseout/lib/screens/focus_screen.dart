// ─────────────────────────────────────────────────────────────
//  lib/screens/focus_screen.dart
//
//  REFACTOR — Allowlist → Blacklist architecture
//
//  Users now select apps TO BLOCK. Everything else is allowed
//  automatically, including all system UI, OEM overlays,
//  launchers, permission dialogs, etc.
//
//  Blocking logic is now three lines:
//    if (!_blockedApps.contains(fg)) → allow
//    if (_neverBlock.contains(fg))   → allow (self + emergency)
//    otherwise                       → stabilize then block
//
//  Also adds time-based foreground stabilization (1500ms) on
//  top of the existing consecutive-count debounce to eliminate
//  false positives from transient system activities.
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app_theme.dart';
import '../channels/usage_channel.dart';
import '../services/focus_service.dart';
import '../widgets/app_picker.dart';

// Packages that can NEVER be blocked regardless of user selection.
// Kept minimal — blacklist model makes most of these unnecessary
// but self-protection and emergency dialer are non-negotiable.
const _neverBlock = <String>{
  'com.brightdev.phaseout',
  'com.android.dialer',
  'com.samsung.android.dialer',
  'com.google.android.dialer',
  'com.android.mms',
  'com.samsung.android.messaging',
  'com.google.android.apps.messaging',
};

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});
  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen>
    with SingleTickerProviderStateMixin {

  bool         _active           = false;
  List<String> _blockedApps      = [];
  Duration     _elapsed          = Duration.zero;
  DateTime?    _startTime;
  String?      _currentBlocked;

  // Debounce state
  String?      _lastSeenPkg;
  int          _consecutiveCount = 0;

  // Time-based stabilization (plan §7)
  DateTime?    _foregroundSince;

  Timer?       _elapsedTicker;
  Timer?       _focusTicker;
  late AnimationController _ringCtrl;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _load();
  }

  Future<void> _load() async {
    final active      = await FocusService.isSessionActive();
    final blockedApps = await FocusService.getBlockedApps();
    if (mounted) {
      setState(() { _active = active; _blockedApps = blockedApps; });
      if (active) {
        _startElapsedTicker();
        _startFocusTicker();
      }
    }
  }

  // ── Overlay permission ────────────────────────────────────
  Future<bool> _ensureOverlayPermission() async {
    final granted = await Permission.systemAlertWindow.isGranted;
    if (granted) return true;
    if (!mounted) return false;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Display over other apps',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
        content: const Text(
          'Focus mode needs to show a block overlay on top of other apps.\n\n'
          'Grant "Display over other apps" permission to enable this.',
          style: TextStyle(
              color: AppTheme.textSecond, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Not now',
                  style: TextStyle(color: AppTheme.textSecond))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Permission.systemAlertWindow.request();
            },
            child: const Text('Grant',
                style: TextStyle(color: AppTheme.accentLight)),
          ),
        ],
      ),
    );
    return await Permission.systemAlertWindow.isGranted;
  }

  void _startElapsedTicker() {
    _startTime ??= DateTime.now();
    _elapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _startTime != null) {
        setState(() => _elapsed = DateTime.now().difference(_startTime!));
      }
    });
  }

  // ── Focus ticker — blacklist model with stabilization ─────
  //
  // A foreground package triggers blocking only when ALL of:
  //   1. It IS in _blockedApps (user explicitly chose to block it)
  //   2. It is NOT in _neverBlock (self-protection + emergency)
  //   3. It has been foreground for ≥ 1500ms (stabilization)
  //   4. It has been seen ≥ 2 consecutive polls (debounce)
  //
  // Everything else — system UI, launchers, OEM overlays,
  // permission dialogs, battery screens — is ignored completely.
  //
  void _startFocusTicker() {
    _focusTicker?.cancel();
    _focusTicker = Timer.periodic(const Duration(milliseconds: 700), (_) async {
      if (!_active || !mounted) return;

      final fg = await UsageChannel.getForegroundApp();
      if (!mounted || fg == null) return;

      // ── Step 1: not in the user's blocked list → allow ────
      if (!_blockedApps.contains(fg)) {
        _clearBlockedState();
        return;
      }

      // ── Step 2: always-safe guard ─────────────────────────
      if (_neverBlock.contains(fg)) {
        _clearBlockedState();
        return;
      }

      // ── Step 3: time-based stabilization ─────────────────
      if (fg == _lastSeenPkg) {
        _consecutiveCount++;
        final stableFor = DateTime.now().difference(_foregroundSince!);
        if (stableFor.inMilliseconds < 1500) return; // not stable yet
      } else {
        _lastSeenPkg      = fg;
        _consecutiveCount = 1;
        _foregroundSince  = DateTime.now();
        return; // start the clock, don't block yet
      }

      // ── Step 4: debounce — must appear twice in a row ─────
      if (_consecutiveCount >= 2 && _currentBlocked != fg && mounted) {
        setState(() => _currentBlocked = fg);
      }
    });
  }

  void _clearBlockedState() {
    if (_currentBlocked != null && mounted) {
      setState(() => _currentBlocked = null);
    }
    _lastSeenPkg      = null;
    _consecutiveCount = 0;
    _foregroundSince  = null;
  }

  Future<void> _start() async {
    if (_blockedApps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Choose at least one app to block first.')));
      return;
    }
    final ok = await _ensureOverlayPermission();
    if (!ok) return;

    await FocusService.startSession(_blockedApps);
    _startTime        = DateTime.now();
    _elapsed          = Duration.zero;
    _consecutiveCount = 0;
    _lastSeenPkg      = null;
    _foregroundSince  = null;
    _startElapsedTicker();
    _startFocusTicker();
    if (mounted) setState(() => _active = true);
  }

  Future<void> _stop() async {
    _elapsedTicker?.cancel();
    _focusTicker?.cancel();
    await FocusService.stopSession();
    if (mounted) {
      setState(() {
        _active           = false;
        _elapsed          = Duration.zero;
        _startTime        = null;
        _currentBlocked   = null;
        _lastSeenPkg      = null;
        _consecutiveCount = 0;
        _foregroundSince  = null;
      });
    }
  }

  Future<void> _editBlockedApps() async {
    List<String> draft = List.from(_blockedApps);
    final result = await showModalBottomSheet<List<String>>(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    AppTheme.navy,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.85, minChildSize: 0.5,
        builder: (_, ctrl) => StatefulBuilder(
          builder: (ctx, setSheet) => Column(children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.textHint,
                  borderRadius: BorderRadius.circular(2))),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Blocked apps',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                  SizedBox(height: 4),
                  Text(
                    'Phone, Messages and Settings are always accessible.',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecond)),
                ]),
            ),
            Expanded(child: SingleChildScrollView(
              controller: ctrl,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppPicker(
                  selected: draft,
                  onChanged: (l) => setSheet(() => draft = l)),
            )),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20,
                  MediaQuery.of(sheetCtx).padding.bottom + 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(sheetCtx, draft),
                  child: Text(
                    'Done — ${draft.length} app${draft.length == 1 ? "" : "s"} selected')),
              ),
            ),
          ]),
        ),
      ),
    );
    if (result != null) setState(() => _blockedApps = result);
  }

  String get _elapsedLabel {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _elapsedTicker?.cancel();
    _focusTicker?.cancel();
    _ringCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(title: const Text('Focus mode')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          Center(child: SizedBox(width: 180, height: 180,
            child: Stack(alignment: Alignment.center, children: [
              if (_active) AnimatedBuilder(
                animation: _ringCtrl,
                builder: (_, __) => CustomPaint(
                  size: const Size(180, 180),
                  painter: _GlowRing(_ringCtrl.value))),
              SizedBox(width: 160, height: 160,
                child: CircularProgressIndicator(
                  value: 1, strokeWidth: 8,
                  backgroundColor: AppTheme.surface2,
                  color: _active
                      ? AppTheme.amber.withValues(alpha: 0.15)
                      : AppTheme.surface2)),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_active ? _elapsedLabel : '00:00',
                  style: const TextStyle(
                      fontFamily: 'DMSerifDisplay',
                      fontSize: 32,
                      color: AppTheme.textPrimary,
                      height: 1)),
                const SizedBox(height: 4),
                Text(_active ? 'elapsed' : 'no session',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecond)),
              ]),
            ]),
          )),
          const SizedBox(height: 24),

          Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: _active
                  ? AppTheme.amber.withValues(alpha: 0.1)
                  : AppTheme.surface,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                  color: _active
                      ? AppTheme.amber.withValues(alpha: 0.3)
                      : AppTheme.border)),
            child: Text(
              _active
                  ? '${_blockedApps.length} app${_blockedApps.length == 1 ? "" : "s"} blocked'
                  : 'No active session',
              style: TextStyle(
                  fontSize: 12,
                  color: _active ? AppTheme.amber : AppTheme.textSecond,
                  fontWeight: FontWeight.w500)))),
          const SizedBox(height: 28),

          if (!_active) ...[
            OutlinedButton.icon(
              onPressed: _editBlockedApps,
              icon: const Icon(Icons.apps_rounded, size: 16),
              label: Text(_blockedApps.isEmpty
                  ? 'Choose apps to block'
                  : '${_blockedApps.length} selected — tap to edit')),
            const SizedBox(height: 12),
          ],

          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: _active ? _stop : _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: _active ? AppTheme.rose : AppTheme.amber,
                padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(
                _active ? 'Stop session' : 'Start focus session',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)))),

          if (_active) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border)),
              child: Row(children: [
                Icon(Icons.timer_rounded,
                    color: _currentBlocked != null
                        ? AppTheme.danger
                        : AppTheme.amber,
                    size: 16),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  _currentBlocked != null
                      ? 'Blocking: $_currentBlocked'
                      : 'Monitoring for blocked apps...',
                  style: TextStyle(
                      fontSize: 12,
                      color: _currentBlocked != null
                          ? AppTheme.danger
                          : AppTheme.textSecond,
                      height: 1.4))),
              ])),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.amber.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.amber.withValues(alpha: 0.15))),
              child: const Text(
                'Phone, Messages and Settings are always accessible during focus.',
                style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textHint,
                    height: 1.4),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GlowRing extends CustomPainter {
  final double t;
  _GlowRing(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final cx    = size.width / 2;
    final cy    = size.height / 2;
    final r     = size.width / 2 - 4;
    final start = -math.pi / 2 + t * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      start, math.pi * 0.8, false,
      Paint()
        ..style      = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap  = StrokeCap.round
        ..shader = SweepGradient(
          colors: [
            AppTheme.amber.withValues(alpha: 0),
            AppTheme.amber.withValues(alpha: 0.7),
            AppTheme.amber.withValues(alpha: 0),
          ],
          startAngle: start,
          endAngle:   start + math.pi * 0.8,
        ).createShader(Rect.fromCircle(
            center: Offset(cx, cy), radius: r)));
  }
  @override bool shouldRepaint(_GlowRing old) => old.t != t;
}