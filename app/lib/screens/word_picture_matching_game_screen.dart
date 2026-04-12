import 'package:flutter/material.dart';
import '../theme/app_design.dart';

class WordPictureMatchingGameScreen extends StatefulWidget {
  static const routeName = '/word-picture-matching-game';
  const WordPictureMatchingGameScreen({super.key});

  @override
  State<WordPictureMatchingGameScreen> createState() => _WordPictureMatchingGameScreenState();
}

class _WordPictureMatchingGameScreenState extends State<WordPictureMatchingGameScreen> {
  final List<Map<String, String>> _items = [
    {'word': 'DOG', 'emoji': '🐶'},
    {'word': 'CAT', 'emoji': '🐱'},
    {'word': 'BIRD', 'emoji': '🐦'},
    {'word': 'FISH', 'emoji': '🐟'},
  ];

  late Map<String, String> _current;
  late List<String> _options;
  int _correct = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  void _newRound() {
    _items.shuffle();
    _current = _items.first;
    _options = _items.map((e) => e['emoji']!).toList();
    _options.shuffle();
    setState(() {});
  }

  void _onTap(String emoji) {
    _total += 1;
    final isCorrect = emoji == _current['emoji'];
    if (isCorrect) {
      _correct += 1;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Great! That matches the word.')),
      );
      _newRound();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not this one. Try another picture.')),
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Word–Picture Matching')),
      body: Padding(
        padding: AppDesign.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Read the word and tap the matching picture.'),
            const SizedBox(height: 12),
            Center(
              child: Text(
                _current['word'] ?? '',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            Text('Correct: $_correct   Total attempts: $_total'),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: _options.length,
                itemBuilder: (context, index) {
                  final emoji = _options[index];
                  return GestureDetector(
                    onTap: () => _onTap(emoji),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade800,
                        borderRadius: BorderRadius.circular(AppDesign.radiusM),
                      ),
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 40),
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

