// lib/screens/scenario_builder_screen.dart
import 'package:flutter/material.dart';
import '../app_theme.dart';

class ScenarioBuilderScreen extends StatelessWidget {
  const ScenarioBuilderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        title: const Text('New scenario'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const Center(
        child: Text('Scenario builder — coming in v1.1',
          style: TextStyle(color: AppTheme.textSecond)),
      ),
    );
  }
}