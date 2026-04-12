import 'dart:math';

import 'package:flutter/material.dart';
import '../theme/app_design.dart';

class VisualSearchGameScreen extends StatefulWidget {
  static const routeName = '/visual-search-game';
  const VisualSearchGameScreen({super.key});

  @override
  State<VisualSearchGameScreen> createState() => _VisualSearchGameScreenState();
}

class _VisualSearchGameScreenState extends State<VisualSearchGameScreen> {
  final Random _rng = Random();
  late String _target;
  late List<String> _grid;
  int _correctTaps = 0;
  int _totalTaps = 0;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  void _newRound() {
    const symbols = ['⭐', '🔺', '🔵'];
    _target = symbols[_rng.nextInt(symbols.length)];
    _grid = List<String>.generate(16, (_) => symbols[_rng.nextInt(symbols.length)]);
    // Make sure at least one target is present.
    _grid[_rng.nextInt(_grid.length)] = _target;
    setState(() {});
  }

  void _onTap(int index) {
    _totalTaps += 1;
    if (_grid[index] == _target) {
      _correctTaps += 1;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nice! You found a target.')),
      );
      _newRound();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That one is not the target. Try again.')),
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visual Search Game')),
      body: Padding(
        padding: AppDesign.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Find and tap every $_target in the grid.'),
            const SizedBox(height: 8),
            Text('Correct taps: $_correctTaps   Total taps: $_totalTaps'),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: _grid.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => _onTap(index),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade800,
                        borderRadius: BorderRadius.circular(AppDesign.radiusM),
                      ),
                      child: Center(
                        child: Text(
                          _grid[index],
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

