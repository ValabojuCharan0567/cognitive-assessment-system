import 'package:flutter/material.dart';

import 'card_matching_game_screen.dart';
import 'visual_search_game_screen.dart';
import 'word_picture_matching_game_screen.dart';
import '../theme/app_design.dart';

class GamesHubScreen extends StatelessWidget {
  static const routeName = '/games-hub';
  const GamesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rawArgs = ModalRoute.of(context)?.settings.arguments;
    final List<dynamic> recs = (rawArgs is Map && rawArgs['recs'] is List)
        ? rawArgs['recs'] as List
        : const [];
    final gameLibraryTotal = (rawArgs is Map)
        ? int.tryParse(
              (rawArgs['gameLibraryTotal'] ?? rawArgs['game_library_total'] ?? '108')
                  .toString(),
            ) ??
            108
        : 108;
    final recommendationNote = (rawArgs is Map)
        ? (rawArgs['recommendationNote'] ?? rawArgs['recommendation_note'] ?? '')
            .toString()
        : '';

    final hasRecs = recs.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cognitive Training Games'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () {
            // Go back to child dashboard
            Navigator.pop(context);
          },
        ),
      ),
      body: ListView(
        padding: AppDesign.pagePadding,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '100+ Game Recommendation System',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    recommendationNote.isNotEmpty
                        ? recommendationNote
                        : 'This catalog includes $gameLibraryTotal+ activities across Memory, Attention, and Language.',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _catalogChip('🧠 Memory', _catalogSizeFor(recs, 'memory', 36)),
                      _catalogChip('🎯 Attention', _catalogSizeFor(recs, 'attention', 36)),
                      _catalogChip('🗣 Language', _catalogSizeFor(recs, 'language', 36)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasRecs
                ? 'Choose a game to start practising. These games are aligned to the areas highlighted in your child\'s report.'
                : 'Choose a game to start practising.',
          ),
          const SizedBox(height: 16),
          if (hasRecs) ..._buildRecommendedCards(context, recs),
          if (!hasRecs) ...[
            const Text(
              'Choose a game to start practising. These games are aligned to the areas highlighted in your child\'s report.',
            ),
            const SizedBox(height: 16),
            const Text(
              '🧠 Memory',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                title: const Text('Card Matching Game'),
                subtitle:
                    const Text('Flip and remember where pairs are hidden.'),
                onTap: () {
                  Navigator.pushNamed(
                      context, CardMatchingGameScreen.routeName);
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '🎯 Attention',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                title: const Text('Visual Search Game'),
                subtitle:
                    const Text('Find the target symbol among distractors.'),
                onTap: () {
                  Navigator.pushNamed(
                      context, VisualSearchGameScreen.routeName);
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '🗣 Language',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                title: const Text('Word–Picture Matching'),
                subtitle: const Text('Tap the picture that matches the word.'),
                onTap: () {
                  Navigator.pushNamed(
                      context, WordPictureMatchingGameScreen.routeName);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _catalogChip(String title, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppDesign.radiusM),
        border: Border.all(color: Colors.white24),
      ),
      child: Text('$title  ($count)'),
    );
  }

  int _catalogSizeFor(List<dynamic> recs, String domainKey, int fallback) {
    for (final r in recs) {
      if (r is Map && (r['domain'] ?? '').toString().toLowerCase() == domainKey) {
        final value = r['catalog_size'];
        if (value is num) return value.toInt();
        final parsed = int.tryParse(value?.toString() ?? '');
        if (parsed != null) return parsed;
      }
    }
    return fallback;
  }

  List<Widget> _buildRecommendedCards(
      BuildContext context, List<dynamic> recs) {
    final Map<String, Map<String, dynamic>> byDomain = {};
    for (final r in recs) {
      if (r is Map) {
        final domain = (r['domain'] ?? '').toString().toLowerCase();
        if (domain.isNotEmpty) byDomain[domain] = r.cast<String, dynamic>();
      }
    }

    Widget domainSection({
      required String domainKey,
      required String title,
    }) {
      final rec = byDomain[domainKey];
      final games = (rec?['games'] ?? []) as List<dynamic>;
      final description = rec?['description']?.toString();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (description != null && description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(description),
            ),
          ...games.take(3).map((game) {
            final gameTitle = game.toString();
            final route = _routeForRecommendedGame(gameTitle);
            return Card(
              child: ListTile(
                title: Text(gameTitle),
                subtitle:
                    const Text('Tap to practise this recommended activity.'),
                onTap: () => Navigator.pushNamed(context, route),
              ),
            );
          }),
          const SizedBox(height: 16),
        ],
      );
    }

    final domainKeys = <String>['memory', 'attention', 'language'];

    final out = <Widget>[];
    for (final k in domainKeys) {
      if (!byDomain.containsKey(k)) continue;
      if (k == 'memory') {
        out.add(domainSection(domainKey: k, title: '🧠 Memory'));
      }
      if (k == 'attention') {
        out.add(domainSection(domainKey: k, title: '🎯 Attention'));
      }
      if (k == 'language') {
        out.add(domainSection(domainKey: k, title: '🗣 Language'));
      }
    }

    // Fallback if backend sent unexpected domains.
    if (out.isEmpty) {
      out.add(const Text('No recommended games found.'));
    }
    return out;
  }

  String _routeForRecommendedGame(String gameTitle) {
    final t = gameTitle.toLowerCase();
    if (t.contains('card') || t.contains('match')) {
      return CardMatchingGameScreen.routeName;
    }
    if (t.contains('visual') ||
        t.contains('search') ||
        t.contains('attention') ||
        t.contains('focus')) {
      return VisualSearchGameScreen.routeName;
    }
    if (t.contains('word') ||
        t.contains('picture') ||
        t.contains('vocabulary') ||
        t.contains('language')) {
      return WordPictureMatchingGameScreen.routeName;
    }
    // Default mapping.
    return CardMatchingGameScreen.routeName;
  }
}
