import 'dart:async';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../services/audio_timer_service.dart';
import '../utils/constants.dart';
import '../widgets/audio_timer_ring.dart';
 
class AudioTimerScreen extends StatefulWidget {
  const AudioTimerScreen({super.key});
  @override
  State<AudioTimerScreen> createState() => _AudioTimerScreenState();
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600,
            color: AppTheme.textHint, letterSpacing: 1.2));
  }
}
 
class _AudioTimerScreenState extends State<AudioTimerScreen> {
  int    _selectedMinutes  = 30;
  bool   _active           = false;
  int?   _remainingSeconds;
  int?   _totalMinutes;
  Timer? _ticker;
 
  @override
  void initState() { super.initState(); _load(); }
 
  Future<void> _load() async {
    final active    = await AudioTimerService.isActive();
    final remaining = await AudioTimerService.remainingSeconds();
    if (mounted) {
      setState(() {
        _active           = active;
        _remainingSeconds = remaining;
        _totalMinutes     = active ? _selectedMinutes : null;
      });
      if (active) _startTicker();
    }
  }
 
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      final remaining = await AudioTimerService.remainingSeconds();
      if (mounted) {
        setState(() => _remainingSeconds = remaining);
        if (remaining == null || remaining <= 0) {
          _ticker?.cancel();
          setState(() { _active = false; _totalMinutes = null; });
        }
      }
    });
  }
 
  Future<void> _start() async {
    await AudioTimerService.start(_selectedMinutes);
    _totalMinutes = _selectedMinutes;
    _startTicker();
    if (mounted) setState(() => _active = true);
  }
 
  Future<void> _cancel() async {
    _ticker?.cancel();
    await AudioTimerService.cancel();
    if (mounted) setState(() { _active = false; _remainingSeconds = null; _totalMinutes = null; });
  }
 
  @override
  void dispose() { _ticker?.cancel(); super.dispose(); }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        title: const Text('Sleep timer'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
 
          // Ring
          Center(
            child: AudioTimerRing(
              totalMinutes:     _totalMinutes,
              remainingSeconds: _remainingSeconds,
            ),
          ),
          const SizedBox(height: 28),
 
          // Duration selector
          if (!_active) ...[
            const _FieldLabel('Duration'),
            const SizedBox(height: 12),
            // Presets
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [15, 30, 45, 60, 90].map((m) {
                final selected = _selectedMinutes == m;
                return GestureDetector(
                  onTap: () => setState(() => _selectedMinutes = m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.teal.withValues(alpha: 0.15)
                          : AppTheme.surface,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: selected
                            ? AppTheme.teal.withValues(alpha: 0.4)
                            : AppTheme.border,
                      ),
                    ),
                    child: Text('${m}m',
                        style: TextStyle(
                          fontSize:   12,
                          color:      selected ? AppTheme.tealLight : AppTheme.textSecond,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Slider
            Row(children: [
              const Text('${AppConstants.audioTimerMinMinutes}m',
                  style: TextStyle(fontSize: 11, color: AppTheme.textHint)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor:   AppTheme.teal,
                    inactiveTrackColor: AppTheme.surface2,
                    thumbColor:         AppTheme.tealLight,
                    overlayColor:       AppTheme.teal.withValues(alpha: 0.15),
                    trackHeight:        3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  ),
                  child: Slider(
                    value:     _selectedMinutes.toDouble(),
                    min:       AppConstants.audioTimerMinMinutes.toDouble(),
                    max:       AppConstants.audioTimerMaxMinutes.toDouble(),
                    divisions: (AppConstants.audioTimerMaxMinutes - AppConstants.audioTimerMinMinutes) ~/ 5,
                    label:     '$_selectedMinutes min',
                    onChanged: (v) => setState(() => _selectedMinutes = v.round()),
                  ),
                ),
              ),
              const Text('${AppConstants.audioTimerMaxMinutes}m',
                  style: TextStyle(fontSize: 11, color: AppTheme.textHint)),
            ]),
            const SizedBox(height: 20),
          ],
 
          // Active status
          if (_active)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:        AppTheme.teal.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.teal.withValues(alpha: 0.2)),
              ),
              child: const Column(children: [
                Text('Music will stop when the timer runs out.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppTheme.textSecond)),
                SizedBox(height: 4),
                Text('Good night 🌙',
                    style: TextStyle(fontSize: 12, color: AppTheme.textHint, fontStyle: FontStyle.italic)),
              ]),
            ),
 
          const SizedBox(height: 20),
 
          // Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _active ? _cancel : _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: _active ? AppTheme.rose : AppTheme.teal,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                _active ? 'Cancel timer' : 'Start $_selectedMinutes min timer',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ),
 
          const SizedBox(height: 16),
          const Text(
            'Start playing music in any app, then start the timer here. PhaseOut will stop the audio automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppTheme.textHint, height: 1.6),
          ),
        ],
      ),
    );
  }
}