// ─────────────────────────────────────────────────────────────
//  lib/screens/focus_screen.dart
//  Shows per-screen intro with SYSTEM_ALERT_WINDOW permission
//  on first open. No skip option.
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app_theme.dart';
import '../services/focus_service.dart';
import '../widgets/app_picker.dart';
import '../widgets/screen_intro_overlay.dart';

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});
  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen>
    with SingleTickerProviderStateMixin {

  bool         _active    = false;
  List<String> _allowlist = [];
  Duration     _elapsed   = Duration.zero;
  DateTime?    _startTime;
  Timer?       _ticker;
  late AnimationController _ringCtrl;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _load();
    // Show intro on first visit
    WidgetsBinding.instance.addPostFrameCallback((_) => _showIntroIfNeeded());
  }

  Future<void> _showIntroIfNeeded() async {
    await ScreenIntroOverlay.showIfNeeded(
      context,
      screenKey: 'focus_screen',
      title:     'Focus mode',
      subtitle:
          'Block distracting apps while you work, study, or unwind.',
      features: const [
        ScreenFeature(
          icon:     Icons.block_rounded,
          color:    Color(0xFFFBBF24),
          title:    'App blocking',
          subtitle: 'Any app not on your allowed list shows a lock overlay',
        ),
        ScreenFeature(
          icon:     Icons.timer_rounded,
          color:    AppTheme.tealLight,
          title:    'Session timer',
          subtitle: 'Track how long you stay focused',
        ),
        ScreenFeature(
          icon:     Icons.picture_in_picture_alt_rounded,
          color:    Color(0xFF60A5FA),
          title:    'Full-screen overlay',
          subtitle: 'A gentle reminder appears over blocked apps',
        ),
      ],
      permission: ScreenPermission(
        icon:  Icons.picture_in_picture_alt_rounded,
        color: const Color(0xFF60A5FA),
        title: 'Display over other apps',
        reason:
            'PhaseOut needs this to show the focus overlay on top of blocked apps like TikTok or Instagram.',
        onGrant: () async {
          await Permission.systemAlertWindow.request();
        },
        checkGranted: () async =>
            await Permission.systemAlertWindow.isGranted,
      ),
    );
  }

  Future<void> _load() async {
    final active    = await FocusService.isSessionActive();
    final allowlist = await FocusService.getAllowlist();
    if (mounted) {
      setState(() { _active = active; _allowlist = allowlist; });
      if (active) _startTicker();
    }
  }

  void _startTicker() {
    _startTime ??= DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _startTime != null) {
        setState(() => _elapsed = DateTime.now().difference(_startTime!));
      }
    });
  }

  Future<void> _start() async {
    if (_allowlist.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add at least one allowed app first.')));
      return;
    }
    await FocusService.startSession(_allowlist);
    _startTime = DateTime.now();
    _elapsed   = Duration.zero;
    _startTicker();
    if (mounted) setState(() => _active = true);
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    await FocusService.stopSession();
    if (mounted) {
      setState(() {
        _active    = false;
        _elapsed   = Duration.zero;
        _startTime = null;
      });
    }
  }

  Future<void> _editAllowlist() async {
    List<String> draft = List.from(_allowlist);
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (_, ctrl) => StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                        color: AppTheme.textHint,
                        borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                const Text('Allowed apps',
                  style: TextStyle(
                      fontSize:   17,
                      fontWeight: FontWeight.w600,
                      color:      AppTheme.textPrimary)),
                const SizedBox(height: 4),
                const Text('Everything else will be blocked.',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecond)),
                const SizedBox(height: 16),
                Expanded(child: SingleChildScrollView(
                  controller: ctrl,
                  child: AppPicker(
                      selected:  draft,
                      onChanged: (l) => setSheet(() => draft = l)),
                )),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(sheetCtx, draft),
                    child:
                        Text('Done — ${draft.length} apps selected'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null) setState(() => _allowlist = result);
  }

  String get _elapsedLabel {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _ticker?.cancel();
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

          // Ring
          Center(
            child: SizedBox(
              width: 180, height: 180,
              child: Stack(alignment: Alignment.center, children: [
                if (_active)
                  AnimatedBuilder(
                    animation: _ringCtrl,
                    builder: (_, __) => CustomPaint(
                      size:    const Size(180, 180),
                      painter: _GlowRing(_ringCtrl.value),
                    ),
                  ),
                SizedBox(
                  width: 160, height: 160,
                  child: CircularProgressIndicator(
                    value:           1,
                    strokeWidth:     8,
                    backgroundColor: AppTheme.surface2,
                    color:           _active
                        ? AppTheme.amber.withValues(alpha: 0.15)
                        : AppTheme.surface2,
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    _active ? _elapsedLabel : '00:00',
                    style: const TextStyle(
                      fontFamily: 'DMSerifDisplay',
                      fontSize:   32,
                      color:      AppTheme.textPrimary,
                      height:     1,
                    )),
                  const SizedBox(height: 4),
                  Text(
                    _active ? 'elapsed' : 'no session',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecond)),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 24),

          // Status
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _active
                    ? AppTheme.amber.withValues(alpha: 0.1)
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: _active
                      ? AppTheme.amber.withValues(alpha: 0.3)
                      : AppTheme.border,
                ),
              ),
              child: Text(
                _active
                    ? '${_allowlist.length} app(s) allowed — all others blocked'
                    : 'No active session',
                style: TextStyle(
                  fontSize:   12,
                  color:      _active ? AppTheme.amber : AppTheme.textSecond,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),

          if (!_active) ...[
            OutlinedButton.icon(
              onPressed: _editAllowlist,
              icon:  const Icon(Icons.apps_rounded, size: 16),
              label: Text(_allowlist.isEmpty
                  ? 'Choose allowed apps'
                  : '${_allowlist.length} app(s) — tap to edit'),
            ),
            const SizedBox(height: 12),
          ],

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _active ? _stop : _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: _active ? AppTheme.rose : AppTheme.amber,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                _active ? 'Stop session' : 'Start focus session',
                style: const TextStyle(
                    fontSize:   15,
                    fontWeight: FontWeight.w600,
                    color:      Colors.white),
              ),
            ),
          ),

          if (_active) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:        AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border:       Border.all(color: AppTheme.border),
              ),
              child: const Row(children: [
                Icon(Icons.block_rounded, color: AppTheme.rose, size: 16),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Apps not on your allowed list will show a lock overlay.',
                    style: TextStyle(
                        fontSize: 12,
                        color:    AppTheme.textSecond,
                        height:   1.5),
                  ),
                ),
              ]),
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
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap   = StrokeCap.round
        ..shader = SweepGradient(
          colors: [
            AppTheme.amber.withValues(alpha: 0),
            AppTheme.amber.withValues(alpha: 0.7),
            AppTheme.amber.withValues(alpha: 0),
          ],
          startAngle: start,
          endAngle:   start + math.pi * 0.8,
        ).createShader(Rect.fromCircle(
            center: Offset(cx, cy), radius: r)),
    );
  }
  @override
  bool shouldRepaint(_GlowRing old) => old.t != t;
}