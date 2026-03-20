import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const PhaseOutApp());
}

class PhaseOutApp extends StatelessWidget {
  const PhaseOutApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'PhaseOut',
      home: Scaffold(
        body: Center(child: Text('PhaseOut — env ready')),
      ),
    );
  }
}