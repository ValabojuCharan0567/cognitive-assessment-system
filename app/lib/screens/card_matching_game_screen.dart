import 'package:flutter/material.dart';
import '../theme/app_design.dart';

class CardMatchingGameScreen extends StatefulWidget {
  static const routeName = '/card-matching-game';
  const CardMatchingGameScreen({super.key});

  @override
  State<CardMatchingGameScreen> createState() => _CardMatchingGameScreenState();
}

class _CardMatchingGameScreenState extends State<CardMatchingGameScreen> {
  static const List<String> _baseIcons = [
    '🐶', '🐱', '🦊', '🐻', '🐸', '🐵', '🐼', '🦁'
  ];
  late List<String> _icons;
  late List<bool> _revealed;
  int? _firstIndex;
  int _matchesFound = 0;
  int _moves = 0;
  bool _busy = false;

  void _resetGame() {
    _icons = List<String>.from(_baseIcons.take(4))
      ..addAll(_baseIcons.take(4));
    _icons.shuffle();
    _revealed = List<bool>.filled(_icons.length, false);
    _firstIndex = null;
    _matchesFound = 0;
    _moves = 0;
    _busy = false;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _resetGame();
  }

  void _onCardTap(int index) {
    if (_revealed[index] || _busy) return;
    setState(() {
      _revealed[index] = true;
    });
    if (_firstIndex == null) {
      _firstIndex = index;
    } else {
      _moves += 1;
      final first = _firstIndex!;
      if (_icons[first] == _icons[index]) {
        _matchesFound += 1;
        _firstIndex = null;
      } else {
        _busy = true;
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!mounted) return;
          setState(() {
            _revealed[first] = false;
            _revealed[index] = false;
            _firstIndex = null;
            _busy = false;
          });
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allMatched = _matchesFound == _icons.length ~/ 2;
    return Scaffold(
      appBar: AppBar(title: const Text('Memory Card Match')),
      body: Padding(
        padding: AppDesign.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Find all the matching pairs!'),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Matches: $_matchesFound'),
                Text('Moves: $_moves'),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Restart',
                  onPressed: _resetGame,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: _icons.length,
                itemBuilder: (context, index) {
                  final revealed = _revealed[index];
                  return GestureDetector(
                    onTap: () => _onCardTap(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: revealed ? Colors.amber.shade100 : Colors.blueGrey.shade800,
                        borderRadius: BorderRadius.circular(AppDesign.radiusM),
                        boxShadow: [
                          if (revealed)
                            BoxShadow(
                              color: Colors.amber.withValues(alpha: 0.3),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          revealed ? _icons[index] : '❓',
                          style: const TextStyle(fontSize: 32),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (allMatched) ...[
              const SizedBox(height: 12),
              const Center(
                child: Column(
                  children: [
                    Icon(Icons.celebration, color: Colors.green, size: 40),
                    SizedBox(height: 8),
                    Text(
                      'Great job! You found all the pairs.',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

