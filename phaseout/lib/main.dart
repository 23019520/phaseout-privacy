import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'channels/media_channel.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'db/database_helper.dart';
import 'models/app_usage_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.initialise();
  await BackgroundService.initialise();
  runApp(const PhaseOutApp());
}

class PhaseOutApp extends StatelessWidget {
  const PhaseOutApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'PhaseOut',
      debugShowCheckedModeBanner: false,
      home: TestScreen(),
    );
  }
}

class TestScreen extends StatefulWidget {
  const TestScreen({super.key});
  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  String _result = 'Ready to test';
  bool _loading = false;
  bool _bgsRunning = false;

  @override
  void initState() {
    super.initState();
    _checkBGS();
  }

  Future<void> _checkBGS() async {
    final running = await BackgroundService.isRunning();
    setState(() => _bgsRunning = running);
  }

  Future<void> _testStopMedia() async {
    setState(() { _loading = true; _result = 'Calling stopAllMedia...'; });
    final success = await MediaChannel.stopAllMedia();
    setState(() {
      _loading = false;
      _result = success ? 'stopAllMedia returned true' : 'stopAllMedia returned false';
    });
  }

  Future<void> _testReleaseAudioFocus() async {
    setState(() { _loading = true; _result = 'Calling releaseAudioFocus...'; });
    final success = await MediaChannel.releaseAudioFocus();
    setState(() {
      _loading = false;
      _result = success ? 'releaseAudioFocus returned true' : 'releaseAudioFocus returned false';
    });
  }

  Future<void> _testStartBGS() async {
    setState(() { _loading = true; _result = 'Starting BGS...'; });
    await BackgroundService.start();
    await Future.delayed(const Duration(seconds: 2));
    await _checkBGS();
    setState(() {
      _loading = false;
      _result = _bgsRunning ? 'BGS is running' : 'BGS did not start - check logs';
    });
  }

  Future<void> _testStopBGS() async {
    setState(() { _loading = true; _result = 'Stopping BGS...'; });
    await BackgroundService.stop();
    await Future.delayed(const Duration(seconds: 2));
    await _checkBGS();
    setState(() {
      _loading = false;
      _result = !_bgsRunning ? 'BGS stopped' : 'BGS still running';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D2137),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('PhaseOut',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 4),
              const Text('Phase 3 - BGS + Bridge Test',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _bgsRunning ? const Color(0xFF065F46) : const Color(0xFF7F1D1D),
                  borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.circle, size: 10,
                    color: _bgsRunning ? Colors.greenAccent : Colors.redAccent),
                  const SizedBox(width: 8),
                  Text(_bgsRunning ? 'BGS running' : 'BGS stopped',
                    style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _checkBGS,
                    child: const Icon(Icons.refresh, size: 14, color: Colors.white38)),
                ])),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A3C5E),
                  borderRadius: BorderRadius.circular(12)),
                child: Text(_result,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.white70))),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: _loading ? null : _testStartBGS,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF059669)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('Start BGS',
                    style: TextStyle(color: Color(0xFF059669), fontSize: 13)))),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton(
                  onPressed: _loading ? null : _testStopBGS,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF9F1239)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('Stop BGS',
                    style: TextStyle(color: Color(0xFF9F1239), fontSize: 13)))),
              ]),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loading ? null : _testStopMedia,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F6FBF),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: _loading
                  ? const SizedBox(height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Test: Stop All Media',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white))),
              const SizedBox(height: 10),
              ElevatedButton(
  onPressed: () async {
    try {
      final rows = await DatabaseHelper.instance.getUsageForDate(
        AppUsageModel.todayString(),
      );
      setState(() {
        _result = 'app_usage_daily exists! Rows today: ${rows.length}';
      });
    } catch (e) {
      setState(() {
        _result = 'TABLE MISSING: $e';
      });
    }
  },
  style: ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFF0F766E),
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
  child: const Text('Test: DB Migration',
    style: TextStyle(color: Colors.white, fontSize: 13)),
),
              OutlinedButton(
                onPressed: _loading ? null : _testReleaseAudioFocus,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF1F6FBF)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Test: Release Audio Focus',
                  style: TextStyle(fontSize: 14, color: Color(0xFF1F6FBF)))),
              const SizedBox(height: 20),
              const Text(
                'Play music then tap Stop All Media.\nCheck status bar for the BGS notification.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
                OutlinedButton(
  onPressed: () async {
    await MediaChannel.openNotificationSettings();
  },
  style: OutlinedButton.styleFrom(
    side: const BorderSide(color: Color(0xFFD97706)),
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
  child: const Text('Grant Notification Access',
    style: TextStyle(fontSize: 13, color: Color(0xFFD97706))),
),
            ],
          ),
        ),
      ),
    );
  }
}