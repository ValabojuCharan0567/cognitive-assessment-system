import 'screens/game_test_hub_screen.dart';
import 'screens/reaction_time_game_screen.dart';
import 'screens/stroop_game_screen.dart';
import 'package:flutter/material.dart';
import 'screens/auth_screen.dart';
import 'screens/child_profile_screen.dart';
import 'screens/eeg_upload_screen.dart';
import 'screens/pre_assessment_screen.dart';
import 'screens/audio_assessment_screen.dart';
import 'screens/results_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/child_dashboard_screen.dart';
import 'screens/games_hub_screen.dart';
import 'screens/card_matching_game_screen.dart';
import 'screens/visual_search_game_screen.dart';
import 'screens/word_picture_matching_game_screen.dart';
import 'theme/app_design.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NeuroAiApp());
}

class NeuroAiApp extends StatelessWidget {
  const NeuroAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neuro-AI Cognitive Assessment',
      debugShowCheckedModeBanner: false,
      theme: AppDesign.theme(),
      initialRoute: AuthScreen.routeName,
      routes: {
        AuthScreen.routeName: (_) => const AuthScreen(),
        ChildProfileScreen.routeName: (_) => const ChildProfileScreen(),
        DashboardScreen.routeName: (_) => const DashboardScreen(),
        ChildDashboardScreen.routeName: (_) => const ChildDashboardScreen(),
        EEGUploadScreen.routeName: (_) => const EEGUploadScreen(),
        PreAssessmentScreen.routeName: (_) => const PreAssessmentScreen(),
        AudioAssessmentScreen.routeName: (_) => const AudioAssessmentScreen(),
        ResultsScreen.routeName: (_) => ResultsScreen(),
        GamesHubScreen.routeName: (_) => const GamesHubScreen(),
        CardMatchingGameScreen.routeName: (_) => const CardMatchingGameScreen(),
        VisualSearchGameScreen.routeName: (_) => const VisualSearchGameScreen(),
        WordPictureMatchingGameScreen.routeName: (_) =>
            const WordPictureMatchingGameScreen(),
        StroopGameScreen.routeName: (_) => throw UnimplementedError(
            'StroopGameScreen requires a task and callback.'),
        ReactionTimeGameScreen.routeName: (_) => throw UnimplementedError(
            'ReactionTimeGameScreen requires a task and callback.'),
        GameTestHubScreen.routeName: (_) => const GameTestHubScreen(),
      },
    );
  }
}
