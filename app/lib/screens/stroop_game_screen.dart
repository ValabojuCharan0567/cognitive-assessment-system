import 'package:flutter/material.dart';
import '../theme/app_design.dart';

// TEMPORARILY DISABLED: StroopGameScreen
class StroopGameScreen extends StatelessWidget {
  static const String routeName = '/stroop-game';
  const StroopGameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Stroop Test")),
      body: Padding(
        padding: AppDesign.pagePadding,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning, size: 60, color: Colors.orange),
              SizedBox(height: 20),
              Text(
                'Stroop Game Coming Soon 🚧',
                style: TextStyle(fontSize: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
