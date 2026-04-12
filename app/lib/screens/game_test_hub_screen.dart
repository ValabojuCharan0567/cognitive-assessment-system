import 'package:flutter/material.dart';
import 'stroop_game_screen.dart';
import 'reaction_time_game_screen.dart';
import '../engine/cognitive_game_engine.dart';
import '../engine/task_templates.dart';
import '../theme/app_design.dart';

class GameTestHubScreen extends StatelessWidget {
  static const routeName = '/game-test-hub';

  const GameTestHubScreen({super.key});

  void _launchStroop(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const StroopGameScreen(),
      ),
    );
  }

  void _launchReaction(BuildContext context) {
    const task = GeneratedTask(
      type: TaskType.processingSpeed,
      instruction: 'Tap as fast as you can when it turns green!',
      options: ['Tap!'],
      correctIndex: 0,
      reactionDelayMs: 1200,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReactionTimeGameScreen(
          task: task,
          onAnswered: (correct, ms) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Reaction: $ms ms')),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Game Test Hub')),
      body: Padding(
        padding: AppDesign.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: () => _launchStroop(context),
              child: const Text('Test Stroop Game'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _launchReaction(context),
              child: const Text('Test Reaction Time Game'),
            ),
          ],
        ),
      ),
    );
  }
}
