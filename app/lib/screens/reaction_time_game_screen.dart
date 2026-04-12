import 'dart:async';
import 'package:flutter/material.dart';
import '../engine/cognitive_game_engine.dart';
import '../theme/app_design.dart';

class ReactionTimeGameScreen extends StatefulWidget {
  static const routeName = '/reaction-time-game';
  final GeneratedTask task;
  final void Function(bool correct, int responseTimeMs) onAnswered;

  const ReactionTimeGameScreen({
    super.key,
    required this.task,
    required this.onAnswered,
  });

  @override
  State<ReactionTimeGameScreen> createState() => _ReactionTimeGameScreenState();
}

class _ReactionTimeGameScreenState extends State<ReactionTimeGameScreen> {
  bool _waiting = true;
  bool _answered = false;
  late DateTime _stimulusTime;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final delay = widget.task.reactionDelayMs ?? 1000;
    _timer = Timer(Duration(milliseconds: delay), () {
      if (!mounted) return;
      setState(() {
        _waiting = false;
        _stimulusTime = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (_answered || _waiting) return;
    _answered = true;
    final responseTime = DateTime.now().difference(_stimulusTime).inMilliseconds;
    widget.onAnswered(true, responseTime);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reaction Time Task')),
      body: Center(
        child: GestureDetector(
          onTap: _handleTap,
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              color: _waiting ? Colors.grey : Colors.green,
              borderRadius: BorderRadius.circular(AppDesign.radiusL),
            ),
            alignment: Alignment.center,
            child: Text(
              _waiting ? 'Wait...' : 'TAP!',
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
