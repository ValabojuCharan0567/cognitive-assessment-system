import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../engine/cognitive_game_engine.dart';
import '../engine/task_templates.dart';
import '../models/assessment_models.dart';
import '../services/api_service.dart';
import 'results_screen.dart';

class PreAssessmentScreen extends StatefulWidget {
  static const routeName = '/pre-assessment';
  const PreAssessmentScreen({super.key});

  @override
  State<PreAssessmentScreen> createState() => _PreAssessmentScreenState();
}

class _PreAssessmentScreenState extends State<PreAssessmentScreen> {
  bool? _lastAnswerCorrect;
  bool _showFeedback = false;
  final _api = ApiService();
  final _generator = TaskGenerator();
  final _recorder = BehavioralRecorder();
  // final _difficulty = DifficultyController();
  FlutterTts? _tts;
  bool _ttsReady = false;
  int _speechRequestId = 0;

  /// Plan: 5 rounds per domain (total 15 tasks).
  static List<TaskType> _buildTaskPlan() {
    const roundsPerDomain = 5;
    final plan = <TaskType>[];
    for (int i = 0; i < roundsPerDomain; i++) {
      plan.add(TaskType.memory);
      plan.add(TaskType.attention);
      plan.add(TaskType.language);
    }
    return plan;
  }

  late final List<TaskType> _taskPlan = _buildTaskPlan();

  int _taskIndex = 0;
  GeneratedTask? _currentTask;
  bool _memoryShowingSequence = false;
  DateTime? _questionStart;
  Timer? _sequenceTimer;
  Timer? _taskTimer;
  static const int _taskTimeSeconds = 15; // seconds per task
  int _secondsLeft = _taskTimeSeconds;

  @override
  void initState() {
    super.initState();
    _initTts();
    _advanceToNextTask();
  }

  Future<void> _initTts() async {
    try {
      final tts = FlutterTts();

      tts.setStartHandler(() {
        debugPrint('[TTS] started');
      });
      tts.setCompletionHandler(() {
        debugPrint('[TTS] completed');
      });
      tts.setErrorHandler((message) {
        debugPrint('[TTS] error: $message');
      });

      await tts.setLanguage('en-US');
      await tts.setSpeechRate(0.4);
      await tts.awaitSpeakCompletion(true);

      if (mounted) {
        setState(() {
          _tts = tts;
          _ttsReady = true;
        });
      } else {
        _tts = tts;
        _ttsReady = true;
      }
    } catch (e) {
      debugPrint('[TTS] init failed: $e');
      if (mounted) {
        setState(() {
          _tts = null;
          _ttsReady = false;
        });
      }
      _tts = null;
      _ttsReady = false;
    }
  }

  Future<void> _speak(String text) async {
    if (_tts == null || !_ttsReady) return;
    final requestId = ++_speechRequestId;

    try {
      await _tts!.stop();
    } catch (e) {
      debugPrint('[TTS] stop warning: $e');
    }

    if (!mounted || requestId != _speechRequestId) {
      return;
    }

    try {
      await _tts!.speak(text);
    } catch (e) {
      debugPrint('[TTS] speak warning: $e');
    }
  }

  @override
  void dispose() {
    _sequenceTimer?.cancel();
    _taskTimer?.cancel();

    if (_tts != null && _ttsReady) {
      _tts!.stop().catchError((_) {
        // ignore: no-op: tts may already be unbound.
      });
    }

    super.dispose();
  }

  DifficultyLevel _difficultyFor(TaskType type) {
    // Pre-assessment stays on a fixed easy baseline so each child starts from
    // the same conditions before the adaptive game modes are introduced.
    return DifficultyLevel.easy;
  }

  int _difficultyIndexFor(TaskType type) {
    switch (_difficultyFor(type)) {
      case DifficultyLevel.easy:
        return 0;
      case DifficultyLevel.medium:
        return 1;
      case DifficultyLevel.hard:
        return 2;
    }
  }

  void _advanceToNextTask() {
    // Cancel any previous timers
    _taskTimer?.cancel();
    _sequenceTimer?.cancel();
    _secondsLeft = _taskTimeSeconds;

    if (_taskIndex >= _taskPlan.length) {
      setState(() {
        _currentTask = null;
        _memoryShowingSequence = false;
      });
      return;
    }
    final type = _taskPlan[_taskIndex];
    final level = _difficultyFor(type);
    final task = _generator.generate(type, level);
    setState(() {
      _currentTask = task;
      _memoryShowingSequence =
          task.type == TaskType.memory && task.sequenceDisplay != null;
      _questionStart = DateTime.now();
      _secondsLeft = _taskTimeSeconds;
    });
    // Start countdown timer
    _taskTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_secondsLeft > 0) {
          _secondsLeft--;
        } else {
          _taskTimer?.cancel();
          // Auto-submit as unanswered/incorrect
          _onAnswer(-1); // -1 means no answer selected
        }
      });
    });
    if (_memoryShowingSequence) {
      unawaited(_speak(task.instruction));
      _sequenceTimer =
          Timer(Duration(milliseconds: task.displayDurationMs), () {
        if (!mounted) return;
        setState(() => _memoryShowingSequence = false);
      });
    } else {
      unawaited(_speak(task.instruction));
    }
  }

  void _onAnswer(int chosenIndex) {
    _taskTimer?.cancel();
    final task = _currentTask;
    if (task == null) return;
    final now = DateTime.now();
    final responseMs = _questionStart != null
        ? now.difference(_questionStart!).inMilliseconds
        : 0;
    final correct = chosenIndex == task.correctIndex;
    _recorder.record(
      task.type,
      correct,
      responseMs,
      _difficultyIndexFor(task.type),
    );
    setState(() {
      _lastAnswerCorrect = (chosenIndex == -1) ? null : correct;
      _showFeedback = true;
    });
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        _showFeedback = false;
        _taskIndex += 1;
      });
      _advanceToNextTask();
    });
  }

  Future<void> _submitAll(Map args) async {
    setState(() {});
    var childId = args['childId'] as String?;
    // Auto-generate test ID if not provided (for testing/demo mode)
    if (childId == null || childId.isEmpty) {
      childId = '1';
    }
    final audioAnalysis = AudioAnalysis.fromJson(
      (args['audioAnalysis'] as Map).cast<String, dynamic>(),
    );
    final eegFeatures = (args['eegFeatures'] as Map?)?.cast<String, dynamic>();
    final assessmentType = (args['assessmentType'] as String?) ?? 'initial';
    final preReportId = args['preReportId']?.toString();
    final features = _recorder.getFeatures();

    if (!audioAnalysis.canSubmit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please complete a valid audio analysis before submitting.'),
        ),
      );
      return;
    }

    if (eegFeatures == null || eegFeatures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please upload and analyse an EEG file before submitting the assessment.'),
        ),
      );
      return;
    }

    try {
      final start = await _api.startAssessment(
        childId,
        type: assessmentType,
        preReportId: preReportId,
      );

      final result = await _api.submitAssessment(
        assessmentId: start['id'],
        eeg: eegFeatures,
        audio: audioAnalysis.toAssessmentPayload(),
        behavioral: features.toJson(),
      );
      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        ResultsScreen.routeName,
        arguments: {
          'child': args['child'],
          'childId': childId,
          'reportType': result['report_type'],
          'type': result['report_type'],
          'createdAt': result['created_at'],
          'created_at': result['created_at'],
          'reportSavedToDashboard': true,
          'summary': result['summary'],
          'scores': result['scores'],
          'analysis': result['analysis'],
          'behavioral': result['behavioral'],
          'comparison': result['comparison'],
          'recommendations': result['recommendations'],
          'audioAnalysis': audioAnalysis,
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analysis failed: $e')),
      );
    }
  }

  Widget _buildStatPill({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              Text(
                value,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStatsPanel(BuildContext context) {
    final f = _recorder.getFeatures();
    final theme = Theme.of(context);
    final timerColor =
        _secondsLeft <= 5 ? Colors.redAccent : theme.colorScheme.secondary;
    final accuracyText =
        f.totalTrials == 0 ? '--' : '${f.accuracyPercent.toStringAsFixed(0)}%';
    final rtText =
        f.totalTrials == 0 ? '--' : '${f.meanReactionMs.toStringAsFixed(0)} ms';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, color: timerColor),
              const SizedBox(width: 8),
              Text(
                '$_secondsLeft s left',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: timerColor,
                ),
              ),
              const Spacer(),
              const Text(
                'Auto-submit on timeout',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _secondsLeft / _taskTimeSeconds,
            minHeight: 7,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: Colors.grey[800],
            valueColor: AlwaysStoppedAnimation<Color>(timerColor),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatPill(
                icon: Icons.track_changes,
                label: 'Accuracy',
                value: accuracyText,
                color: theme.colorScheme.primary,
              ),
              _buildStatPill(
                icon: Icons.bolt_outlined,
                label: 'Avg RT',
                value: rtText,
                color: theme.colorScheme.tertiary,
              ),
              _buildStatPill(
                icon: Icons.checklist_rounded,
                label: 'Answered',
                value: '${f.totalTrials}/${_taskPlan.length}',
                color: theme.colorScheme.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskContent(GeneratedTask task) {
    if (task.type == TaskType.memory &&
        _memoryShowingSequence &&
        task.sequenceDisplay != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Memory Task',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(task.instruction),
          const SizedBox(height: 16),
          Center(
            child: Text(
              task.sequenceDisplay!,
              style: const TextStyle(fontSize: 28),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('Remember the sequence…',
                style: TextStyle(fontStyle: FontStyle.italic)),
          ),
        ],
      );
    }

    String title;
    switch (task.type) {
      case TaskType.memory:
        title = 'Memory Task';
        break;
      case TaskType.attention:
        title = 'Attention Task';
        break;
      case TaskType.language:
        title = 'Language Task';
        break;
      case TaskType.executiveFunction:
        title = 'Executive Function Task';
        break;
      default:
        title = 'Task';
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(task.instruction),
        const SizedBox(height: 16),
        ...List.generate(task.options.length, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _onAnswer(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    task.options[i],
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map;

    if (_currentTask != null) {
      final progress = (_taskIndex + 1) / _taskPlan.length;
      final percent = (progress * 100).clamp(0, 100).toInt();
      return Scaffold(
        appBar: AppBar(
          title: Text(
              'Pre‑Assessment — Task ${_taskIndex + 1} of ${_taskPlan.length}'),
        ),
        body: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Progress bar and percentage
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: Colors.grey[800],
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.secondary),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('$percent%',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  _buildLiveStatsPanel(context),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _buildTaskContent(_currentTask!),
                    ),
                  ),
                ],
              ),
            ),
            // Feedback overlay
            if (_showFeedback)
              Positioned.fill(
                child: Container(
                  color: (_lastAnswerCorrect == null)
                      ? Colors.black.withValues(alpha: 0.55)
                      : _lastAnswerCorrect!
                          ? Colors.green.withValues(alpha: 0.72)
                          : Colors.red.withValues(alpha: 0.72),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_lastAnswerCorrect == null)
                          const Icon(Icons.timer_off_outlined,
                              color: Colors.white, size: 80)
                        else if (_lastAnswerCorrect!)
                          const Icon(Icons.check_circle,
                              color: Colors.white, size: 80)
                        else
                          const Icon(Icons.cancel,
                              color: Colors.white, size: 80),
                        const SizedBox(height: 12),
                        Text(
                          _lastAnswerCorrect == null
                              ? 'Time Up!'
                              : _lastAnswerCorrect!
                                  ? 'Correct!'
                                  : 'Incorrect',
                          style: const TextStyle(
                            fontSize: 32,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _lastAnswerCorrect == null
                              ? 'Moved to the next task automatically.'
                              : 'Tracking accuracy and reaction time.',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Summary step
    final f = _recorder.getFeatures();
    return Scaffold(
      appBar: AppBar(title: const Text('Pre‑Assessment Summary')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatPill(
                  icon: Icons.track_changes,
                  label: 'Accuracy',
                  value: '${f.accuracyPercent.toStringAsFixed(1)}%',
                ),
                _buildStatPill(
                  icon: Icons.bolt_outlined,
                  label: 'Avg RT',
                  value: '${f.meanReactionMs.toStringAsFixed(0)} ms',
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                _buildStatPill(
                  icon: Icons.timer_off_outlined,
                  label: 'Timed out',
                  value: '${f.omissionCount}',
                  color: Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Behavioral results (exact score + percentage):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Memory: ${f.memoryCorrect}/${f.memoryTotal} '
              '(${f.memoryAccuracy.toStringAsFixed(1)}%)',
            ),
            Text(
              'Attention: ${f.attentionCorrect}/${f.attentionTotal} '
              '(${f.attentionAccuracy.toStringAsFixed(1)}%)',
            ),
            Text(
              'Language: ${f.languageCorrect}/${f.languageTotal} '
              '(${f.languageAccuracy.toStringAsFixed(1)}%)',
            ),
            const SizedBox(height: 12),
            Text(
              'Overall: ${f.correctCount}/${f.totalTrials} '
              '(${f.accuracyPercent.toStringAsFixed(1)}%)',
            ),
            Text(
                'Avg reaction time: ${f.meanReactionMs.toStringAsFixed(0)} ms'),
            Text('Auto-submitted / timed out: ${f.omissionCount}'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _submitAll(args),
                child: const Text('Analyse & Generate Report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
