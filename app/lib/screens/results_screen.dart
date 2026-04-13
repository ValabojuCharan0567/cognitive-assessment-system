import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'child_dashboard_screen.dart';
import 'games_hub_screen.dart';
import '../services/report_export_service.dart';
import '../theme/app_design.dart';

/// Dedupe snackbars if the same saved report is opened twice.
final _reportSaveSnackOnce = <String>{};

String _formatSavedOnDisplay(String raw) {
  final dt = DateTime.tryParse(raw);
  if (dt == null) {
    if (raw.isEmpty) return '-';
    return raw.contains('T') ? raw.split('T').first : raw;
  }
  final d =
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  final t =
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  return '$d $t';
}

class ResultsScreen extends StatelessWidget {
  static const routeName = '/results';
  final ReportExportService _reportExport = ReportExportService();

  ResultsScreen({super.key});

  Future<void> _handleExportAction({
    required BuildContext context,
    required String action,
    Map<String, dynamic>? child,
    required String reportType,
    required String createdAt,
    required String summary,
    required Map<String, dynamic> scores,
    required Map<String, dynamic> analysis,
    required Map<String, dynamic> behavioral,
    required Map<String, dynamic> comparison,
    required List<dynamic> recommendations,
  }) async {
    try {
      if (action == 'share') {
        await _reportExport.shareReportPdf(
          child: child,
          reportType: reportType,
          createdAt: createdAt,
          summary: summary,
          scores: scores,
          analysis: analysis,
          behavioral: behavioral,
          comparison: comparison,
          recommendations: recommendations,
        );
      } else {
        await _reportExport.previewReportPdf(
          child: child,
          reportType: reportType,
          createdAt: createdAt,
          summary: summary,
          scores: scores,
          analysis: analysis,
          behavioral: behavioral,
          comparison: comparison,
          recommendations: recommendations,
        );
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'share'
                ? 'PDF report is ready to share.'
                : 'PDF preview opened.',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export report: $e')),
      );
    }
  }

  String _formatMetricNum(double v) {
    final abs = v.abs();
    if (abs < 1e-6) return '0.00';
    if (abs < 1e-2) return v.toStringAsExponential(2);
    // Default: show two decimals for readability (e.g., 2.33, 47.50)
    return v.toStringAsFixed(2);
  }

  Color _scoreColor(double value) {
    if (value >= 75) return const Color(0xFF38D27A);
    if (value >= 50) return const Color(0xFFFFC857);
    return const Color(0xFFFF6B6B);
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;

    if (args == null) {
      return const Scaffold(
        body: Center(child: Text("No data")),
      );
    }

    final reportSaved = args['reportSavedToDashboard'] == true ||
        args['reportSavedToDashboard'] == 'true';
    final createdAtRaw =
        (args['created_at'] ?? args['createdAt'] ?? '').toString();
    if (reportSaved &&
        createdAtRaw.isNotEmpty &&
        !_reportSaveSnackOnce.contains(createdAtRaw)) {
      _reportSaveSnackOnce.add(createdAtRaw);
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Report saved to your dashboard. Use Home to return and see it listed.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      });
    }

    final analysis = (args['analysis'] ?? {}) as Map;
    final behavioral = (args['behavioral'] ?? {}) as Map;
    final comparison = (args['comparison'] is Map)
        ? Map<String, dynamic>.from(args['comparison'] as Map)
        : <String, dynamic>{};
    final deltas = (args['deltas'] is Map)
        ? Map<String, dynamic>.from(args['deltas'] as Map)
        : <String, dynamic>{};
    final trends = (args['trends'] is Map)
        ? Map<String, dynamic>.from(args['trends'] as Map)
        : <String, dynamic>{};
    final recs = (args['recs'] ?? const []) as List;
    final summary = (args['summary'] ?? '') as String;
    final reportType =
        (args['type'] ?? args['reportType'] ?? 'pre').toString();
    final createdAt =
        (args['created_at'] ?? args['createdAt'] ?? '').toString();
    final gameLibraryTotal = int.tryParse(
          (args['game_library_total'] ?? args['gameLibraryTotal'] ?? '108')
              .toString(),
        ) ??
        108;
    final recommendationNote =
        (args['recommendation_note'] ?? args['recommendationNote'] ?? '')
            .toString();
    final recommendationLogic = (args['recommendation_logic'] is Map)
        ? Map<String, dynamic>.from(args['recommendation_logic'] as Map)
        : <String, dynamic>{};
    final weakAreasDetected = (args['weak_areas_detected'] as List?)
            ?.map((e) {
              if (e is Map) {
                return (e['domain'] ?? '').toString();
              }
              return e.toString();
            })
            .where((e) => e.trim().isNotEmpty)
            .toList() ??
        recs
            .whereType<Map>()
            .map((e) => (e['domain'] ?? '').toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();

    final child = (args['child'] is Map) ? (args['child'] as Map) : null;
    final childId = (args['childId'] ?? args['child_id'])?.toString();

    final eeg = (analysis['eeg'] ?? {}) as Map;
    final audio = (analysis['audio'] ?? {}) as Map;

    double? effortFromEeg() {
      final v = eeg['effort'];
      if (v is num) return v.toDouble();
      return null;
    }

    String effortMeaning(double effort) {
      if (effort >= 0.75) return 'High effort';
      if (effort >= 0.5) return 'Moderate effort';
      return 'Low effort';
    }

    String formatPercent01(dynamic value) {
      if (value is num) {
        return '${(value.toDouble() * 100).toStringAsFixed(0)}%';
      }
      return '-';
    }

    String loadMeaning(String loadLevel, double effort) {
      final l = loadLevel.toLowerCase();
      if (l == 'high' || effort >= 0.75) {
        return 'High load: brain activity looks elevated compared to typical focused tasks.';
      }
      if (l == 'low' || effort < 0.35) {
        return 'Low load: brain activity looks relaxed compared to typical focused tasks.';
      }
      return 'Medium load: brain activity was in a typical range for focused tasks.';
    }

    int audioClassFromFluencyScore(dynamic fluencyScore) {
      if (fluencyScore is num) {
        final s = fluencyScore.toDouble();
        if (s < 45) return 0;
        if (s < 75) return 1;
        return 2;
      }
      return 1;
    }

    final effort = effortFromEeg();
    final loadLevel = (eeg['load_level'] ?? '-').toString();
    final effortLabel =
        effort != null ? effortMeaning(effort) : 'Not available';
    final loadSummary =
        effort != null ? loadMeaning(loadLevel, effort) : 'Not available';

    final fluencyLabel = (audio['fluency_label'] ?? '-').toString();
    final fluencyClass = audioClassFromFluencyScore(audio['fluency_score']);
    final fluencyScoreValue = (audio['fluency_score'] is num)
        ? (audio['fluency_score'] as num).toDouble()
        : null;
    final audioMeaning = () {
      final l = fluencyLabel.toLowerCase();
      if (l == 'high') {
        return 'High fluency: speech was strong for this kind of task.';
      }
      if (l == 'low') {
        return 'Low fluency: speech pace suggested extra support may help.';
      }
      return 'Medium fluency: speech was in a typical range for this kind of task.';
    }();

    final overallScore = analysis['cognitive_score'];
    final overallScoreValue =
        overallScore is num ? overallScore.toDouble() : null;
    final behavioralScoreValue = (analysis['behavioral_score'] is num)
        ? (analysis['behavioral_score'] as num).toDouble()
        : null;
    final eegScoreValue = (analysis['eeg_score'] is num)
        ? (analysis['eeg_score'] as num).toDouble()
        : null;
    final audioScoreValue = (analysis['audio_score'] is num)
        ? (analysis['audio_score'] as num).toDouble()
        : null;
    final behavioralAccuracy = (behavioral['accuracy_percent'] is num)
        ? (behavioral['accuracy_percent'] as num).toDouble()
        : null;
    final meanReactionMs = (behavioral['mean_reaction_ms'] is num)
        ? (behavioral['mean_reaction_ms'] as num).toDouble()
        : null;
    final omissionCount = (behavioral['omission_count'] is num)
        ? (behavioral['omission_count'] as num).toInt()
        : null;
    final eegConfidence = eeg['confidence'] != null
        ? formatPercent01(eeg['confidence'])
        : null;
    final audioConfidence = audio['confidence'] is num
        ? '${((audio['confidence'] as num).toDouble() * 100).toStringAsFixed(0)}%'
        : (audio['confidence']?.toString());
    final fusionWeightsText = analysis['fusion_weights'] is Map
        ? () {
            final w = analysis['fusion_weights'] as Map;
            final b = w['behavioral'] ?? '-';
            final e = w['eeg'] ?? '-';
            final a = w['audio'] ?? '-';
            return 'B:$b  E:$e  A:$a';
          }()
        : '-';
    final comparisonSummary = (comparison['summary'] ?? '').toString();
    final comparisonAverage = _asDouble(comparison['average_change']);
    final comparisonDomains = (comparison['domains'] is Map)
        ? Map<String, dynamic>.from(comparison['domains'] as Map)
        : <String, dynamic>{};

    double? comparisonDelta(String key) {
      final direct = _asDouble(deltas[key]);
      if (direct != null) return direct;
      final domain = comparisonDomains[key];
      if (domain is Map) {
        return _asDouble(domain['delta']);
      }
      return null;
    }

    String comparisonTrend(String key) {
      final direct = trends[key]?.toString();
      if (direct != null && direct.isNotEmpty) return direct;
      final domain = comparisonDomains[key];
      if (domain is Map) {
        return (domain['trend'] ?? 'no_change').toString();
      }
      return 'no_change';
    }

    final overallBehaviorFallback = behavioralAccuracy ?? 0.0;
    final scoreBars = <_ChartDatum>[
      if (overallScoreValue != null)
        _ChartDatum(
          'Overall',
          overallScoreValue,
          _scoreColor(overallScoreValue),
        ),
      if (behavioralScoreValue != null)
        _ChartDatum(
          'Behavioral',
          behavioralScoreValue,
          _scoreColor(behavioralScoreValue),
        ),
      if (eegScoreValue != null)
        _ChartDatum('EEG', eegScoreValue, _scoreColor(eegScoreValue)),
      if (audioScoreValue != null)
        _ChartDatum('Audio', audioScoreValue, _scoreColor(audioScoreValue)),
    ];

    final skillRadar = <_ChartDatum>[
      _ChartDatum(
        'Memory',
        _asDouble(behavioral['memory_accuracy']) ?? overallBehaviorFallback,
        const Color(0xFF6EA8FF),
      ),
      _ChartDatum(
        'Attention',
        _asDouble(behavioral['attention_accuracy']) ?? overallBehaviorFallback,
        const Color(0xFF38D27A),
      ),
      _ChartDatum(
        'Language',
        _asDouble(behavioral['language_accuracy']) ?? overallBehaviorFallback,
        const Color(0xFFFFC857),
      ),
      _ChartDatum(
        'Executive',
        (_asDouble(behavioral['executive_total']) ?? 0) > 0
            ? (_asDouble(behavioral['executive_accuracy']) ?? overallBehaviorFallback)
            : overallBehaviorFallback,
        const Color(0xFFFF8A65),
      ),
      _ChartDatum(
        'Reaction',
        (_asDouble(behavioral['reaction_total']) ?? 0) > 0
            ? (_asDouble(behavioral['reaction_accuracy']) ?? overallBehaviorFallback)
            : overallBehaviorFallback,
        const Color(0xFF9B8CFF),
      ),
      _ChartDatum(
        'Work mem',
        (_asDouble(behavioral['working_memory_total']) ?? 0) > 0
            ? (_asDouble(behavioral['working_memory_accuracy']) ?? overallBehaviorFallback)
            : overallBehaviorFallback,
        const Color(0xFF00E0C7),
      ),
    ];

    final trendScores = <double>[];
    final trendLabels = <String>[];
    final historyRaw = args['history'] ?? args['reports'];
    if (historyRaw is List) {
      for (final raw in historyRaw.whereType<Map>()) {
        final entry = Map<String, dynamic>.from(raw);
        final nestedAnalysis = entry['analysis'] is Map
            ? Map<String, dynamic>.from(entry['analysis'] as Map)
            : entry;
        final score = _asDouble(
          nestedAnalysis['cognitive_score'] ?? entry['cognitive_score'],
        );
        if (score == null) continue;
        trendScores.add(score);
        final rawLabel =
            (entry['created_at']?.toString() ?? entry['type']?.toString() ?? 'Now')
                .split('T')
                .first;
        trendLabels.add(
          rawLabel.length > 5 ? rawLabel.substring(rawLabel.length - 5) : rawLabel,
        );
      }
    }
    if (trendScores.isEmpty && overallScoreValue != null) {
      trendScores.add(overallScoreValue);
      trendLabels.add('Now');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Cognitive Profile"),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Export report',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onSelected: (value) async {
              await _handleExportAction(
                context: context,
                action: value,
                child: child != null ? Map<String, dynamic>.from(child) : null,
                reportType: reportType,
                createdAt: createdAt,
                summary: summary,
                scores: Map<String, dynamic>.from((args['scores'] ?? {}) as Map),
                analysis: Map<String, dynamic>.from(analysis),
                behavioral: Map<String, dynamic>.from(behavioral),
                comparison: comparison,
                recommendations: recs,
              );
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'preview',
                child: Text('Preview / Print PDF'),
              ),
              PopupMenuItem<String>(
                value: 'share',
                child: Text('Share PDF'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Dashboard',
            onPressed: () {
              final Map<String, dynamic> dashArgs;
              if (child != null) {
                dashArgs = Map<String, dynamic>.from(child);
              } else if (childId != null && childId.isNotEmpty) {
                dashArgs = {'id': childId};
              } else {
                return;
              }
              Navigator.pushNamedAndRemoveUntil(
                context,
                ChildDashboardScreen.routeName,
                (route) => false,
                arguments: dashArgs,
              );
            },
            icon: const Icon(Icons.home),
          ),
        ],
      ),
      body: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - value)),
              child: child,
            ),
          );
        },
        child: SingleChildScrollView(
          child: Padding(
            padding: AppDesign.pagePadding,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Clinical Summary",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.isEmpty ? "-" : summary,
                      style: const TextStyle(fontSize: 13.5, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    _rowLabelValue(
                      'Report type',
                      reportType.toLowerCase() == 'post'
                          ? 'Post-Test Profile'
                          : 'Pre-Test Profile',
                    ),
                    if (createdAt.isNotEmpty)
                      _rowLabelValue('Saved on', _formatSavedOnDisplay(createdAt)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Overall Cognitive Score",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: (overallScoreValue != null
                                  ? _scoreColor(overallScoreValue)
                                  : Colors.grey)
                              .withValues(alpha: 0.18),
                          child: Icon(
                            Icons.psychology_alt_outlined,
                            color: overallScoreValue != null
                                ? _scoreColor(overallScoreValue)
                                : Colors.white70,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                overallScoreValue != null
                                    ? _formatMetricNum(overallScoreValue)
                                    : '-',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                (analysis['cognitive_level'] ?? 'Combined score').toString(),
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        if (overallScoreValue != null) _statusChip(overallScoreValue),
                      ],
                    ),
                    if (overallScoreValue != null) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: (overallScoreValue / 100).clamp(0.0, 1.0),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(999),
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _scoreColor(overallScoreValue),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (analysis['cognitive_efficiency'] != null)
                          _statBadge(
                            context,
                            icon: Icons.speed_outlined,
                            label: 'Efficiency',
                            value: analysis['cognitive_efficiency'].toString(),
                            color: const Color(0xFF38D27A),
                          ),
                        _statBadge(
                          context,
                          icon: Icons.balance_outlined,
                          label: 'Weights',
                          value: fusionWeightsText,
                          color: const Color(0xFF6EA8FF),
                        ),
                        if (eegConfidence != null)
                          _statBadge(
                            context,
                            icon: Icons.verified_outlined,
                            label: 'EEG confidence',
                            value: eegConfidence,
                            color: const Color(0xFF9B8CFF),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Score bands: Strong (>=75), Developing (50-74), Needs Support (<50)',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Score Breakdown",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _metricCard(
                    context,
                    icon: Icons.sports_esports_outlined,
                    label: 'Behavioral',
                    value: behavioralScoreValue != null
                        ? _formatMetricNum(behavioralScoreValue)
                        : '-',
                    subtitle: behavioralAccuracy != null
                        ? 'Accuracy ${behavioralAccuracy.toStringAsFixed(1)}%'
                        : 'Accuracy unavailable',
                    color: behavioralScoreValue != null
                        ? _scoreColor(behavioralScoreValue)
                        : const Color(0xFFFFC857),
                    scoreValue: behavioralScoreValue,
                  ),
                  _metricCard(
                    context,
                    icon: Icons.graphic_eq_rounded,
                    label: 'EEG',
                    value: eegScoreValue != null
                        ? _formatMetricNum(eegScoreValue)
                        : '-',
                    subtitle: eegConfidence != null
                        ? 'Confidence $eegConfidence'
                        : 'Load $loadLevel',
                    color: eegScoreValue != null
                        ? _scoreColor(eegScoreValue)
                        : const Color(0xFF6EA8FF),
                    scoreValue: eegScoreValue,
                  ),
                  _metricCard(
                    context,
                    icon: Icons.mic_none_rounded,
                    label: 'Audio',
                    value: audioScoreValue != null
                        ? _formatMetricNum(audioScoreValue)
                        : '-',
                    subtitle: audioConfidence != null
                        ? 'Confidence $audioConfidence'
                        : 'Fluency $fluencyLabel',
                    color: audioScoreValue != null
                        ? _scoreColor(audioScoreValue)
                        : const Color(0xFF38D27A),
                    scoreValue: audioScoreValue,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                "Visualizations",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bar Chart (Scores)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Overall and modality score comparison',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 180,
                      child: CustomPaint(
                        painter: _BarChartPainter(scoreBars),
                        child: Container(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Radar Chart (Skills)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Memory, attention, language, executive, reaction, and working memory',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 220,
                      child: CustomPaint(
                        painter: _RadarChartPainter(skillRadar),
                        child: Container(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trend Chart (History)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      trendScores.length > 1
                        ? 'Trend based on saved assessments'
                          : 'Additional points appear after future saved reports.',
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 170,
                      child: CustomPaint(
                        painter: _MiniTrendChartPainter(trendScores, trendLabels),
                        child: Container(),
                      ),
                    ),
                  ],
                ),
              ),
              if (effort != null || eegScoreValue != null) ...[
                const SizedBox(height: 12),
                _panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Brainwave Visualization',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'EEG-inspired activity pattern (visual aid)',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 120,
                        child: CustomPaint(
                          painter: _BrainWavePainter(
                            seed: (effort ?? ((eegScoreValue ?? 50) / 100))
                                .clamp(0.0, 1.0),
                          ),
                          child: Container(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (recs.isNotEmpty || recommendationNote.isNotEmpty) ...[
                const SizedBox(height: 14),
                _panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recommendation Framework',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        recommendationNote.isNotEmpty
                            ? recommendationNote
                            : 'This report selects interventions from a 100+ activity library across Memory, Attention, and Language.',
                        style: const TextStyle(fontSize: 13.5, height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _statBadge(
                            context,
                            icon: Icons.videogame_asset_outlined,
                            label: 'Catalog',
                            value: '$gameLibraryTotal+ games',
                            color: const Color(0xFF38D27A),
                          ),
                          _statBadge(
                            context,
                            icon: Icons.memory_outlined,
                            label: 'Memory',
                            value: 'Category',
                            color: const Color(0xFF6EA8FF),
                          ),
                          _statBadge(
                            context,
                            icon: Icons.center_focus_strong,
                            label: 'Attention',
                            value: 'Category',
                            color: const Color(0xFFFFC857),
                          ),
                          _statBadge(
                            context,
                            icon: Icons.translate_outlined,
                            label: 'Language',
                            value: 'Category',
                            color: const Color(0xFF9B8CFF),
                          ),
                        ],
                      ),
                      if (weakAreasDetected.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Priority support areas: ${weakAreasDetected.map((e) => e[0].toUpperCase() + e.substring(1)).join(', ')}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                      if (recommendationLogic.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Selection rule: ${recommendationLogic['rule'] ?? '2-3 games per priority category'}',
                          style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (recs.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  "Recommended Practice Plan",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ...recs
                    .whereType<Map>()
                    .map((rec) => _recommendationCard(rec)),
              ],
              if (comparison.isNotEmpty || deltas.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text(
                  "Pre/Post Comparison",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                _panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (comparisonAverage != null)
                        Row(
                          children: [
                            const Icon(Icons.compare_arrows_outlined,
                                color: Colors.purpleAccent),
                            const SizedBox(width: 8),
                            Text(
                              'Average change: ${comparisonAverage >= 0 ? '+' : ''}${comparisonAverage.toStringAsFixed(1)}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      if (comparisonSummary.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          comparisonSummary,
                          style: const TextStyle(fontSize: 13.5, height: 1.4),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _statBadge(
                            context,
                            icon: Icons.memory_outlined,
                            label: 'Memory',
                            value: () {
                              final delta = comparisonDelta('memory') ?? 0;
                              return '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}';
                            }(),
                            color: _trendColor(comparisonTrend('memory')),
                          ),
                          _statBadge(
                            context,
                            icon: Icons.center_focus_strong,
                            label: 'Attention',
                            value: () {
                              final delta = comparisonDelta('attention') ?? 0;
                              return '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}';
                            }(),
                            color: _trendColor(comparisonTrend('attention')),
                          ),
                          _statBadge(
                            context,
                            icon: Icons.translate_outlined,
                            label: 'Language',
                            value: () {
                              final delta = comparisonDelta('language') ?? 0;
                              return '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}';
                            }(),
                            color: _trendColor(comparisonTrend('language')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Text(
                "Analysis Breakdown (EEG + Audio + Behavioral)",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _breakdownRow(
                        "Overall cognitive", analysis['cognitive_score']),
                    if (analysis['cognitive_level'] != null)
                      _rowLabelValue(
                          "Level", analysis['cognitive_level'].toString()),
                    if (analysis['difficulty_weight'] != null)
                      _rowLabelValue(
                          "Difficulty", 'x${analysis['difficulty_weight']}'),
                    if (analysis['cognitive_efficiency'] != null)
                      _rowLabelValue("Efficiency",
                          analysis['cognitive_efficiency'].toString()),
                    _rowLabelValue("Weights", fusionWeightsText),
                    _breakdownRow("Behavioral", analysis['behavioral_score']),
                    _breakdownRow("EEG", analysis['eeg_score']),
                    _breakdownRow("Audio", analysis['audio_score']),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "EEG Analysis",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statBadge(
                          context,
                          icon: Icons.layers_outlined,
                          label: 'Load',
                          value: loadLevel,
                          color: const Color(0xFF6EA8FF),
                        ),
                        _statBadge(
                          context,
                          icon: Icons.psychology_outlined,
                          label: 'Effort',
                          value: effort != null ? formatPercent01(effort) : '-',
                          color: const Color(0xFF9B8CFF),
                        ),
                        if (eeg['confidence'] != null)
                          _statBadge(
                            context,
                            icon: Icons.verified_outlined,
                            label: 'Confidence',
                            value: formatPercent01(eeg['confidence']),
                            color: const Color(0xFF38D27A),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _rowLabelValue("Load level", loadLevel),
                    _rowLabelValue(
                      "Effort",
                      effort != null
                          ? '${formatPercent01(effort)} (${_formatMetricNum(effort)})'
                          : '-',
                    ),
                    if (eeg['confidence'] != null)
                      _rowLabelValue(
                        "Confidence",
                        formatPercent01(eeg['confidence']),
                      ),
                    _rowLabelValue("Effort meaning", effortLabel),
                    Text(loadSummary,
                        style: const TextStyle(fontSize: 13.5, height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Audio Analysis",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statBadge(
                          context,
                          icon: Icons.record_voice_over_outlined,
                          label: 'Fluency',
                          value: fluencyLabel,
                          color: const Color(0xFF38D27A),
                        ),
                        _statBadge(
                          context,
                          icon: Icons.equalizer_rounded,
                          label: 'Score',
                          value: fluencyScoreValue != null
                              ? fluencyScoreValue.toStringAsFixed(0)
                              : '-',
                          color: const Color(0xFFFFC857),
                        ),
                        if (audio['confidence'] != null)
                          _statBadge(
                            context,
                            icon: Icons.verified_outlined,
                            label: 'Confidence',
                            value: (audio['confidence'] is num)
                                ? '${((audio['confidence'] as num).toDouble() * 100).toStringAsFixed(0)}%'
                                : audio['confidence'].toString(),
                            color: const Color(0xFF6EA8FF),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _rowLabelValue("Fluency", fluencyLabel),
                    _rowLabelValue("Class", fluencyClass.toString()),
                    _rowLabelValue(
                      "Score",
                      fluencyScoreValue != null
                          ? fluencyScoreValue.toStringAsFixed(0)
                          : '-',
                    ),
                    if (audio['confidence'] != null)
                      _rowLabelValue(
                        "Confidence",
                        (audio['confidence'] is num)
                            ? '${((audio['confidence'] as num).toDouble() * 100).toStringAsFixed(0)}%'
                            : audio['confidence'].toString(),
                      ),
                    Text(audioMeaning,
                        style: const TextStyle(fontSize: 13.5, height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Behavioral Results",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statBadge(
                          context,
                          icon: Icons.track_changes,
                          label: 'Accuracy',
                          value: behavioralAccuracy != null
                              ? '${behavioralAccuracy.toStringAsFixed(1)}%'
                              : '-',
                          color: const Color(0xFFFFC857),
                        ),
                        _statBadge(
                          context,
                          icon: Icons.bolt_outlined,
                          label: 'Avg RT',
                          value: meanReactionMs != null
                              ? '${meanReactionMs.toStringAsFixed(0)} ms'
                              : '-',
                          color: const Color(0xFF6EA8FF),
                        ),
                        _statBadge(
                          context,
                          icon: Icons.timer_off_outlined,
                          label: 'Timed out',
                          value: omissionCount?.toString() ?? '-',
                          color: Colors.orange,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (context) {
                        final correctCount = behavioral['correct_count'];
                        final totalTrials = behavioral['total_trials'];
                        final acc = behavioral['accuracy_percent'];
                        final correct =
                            correctCount is num ? correctCount.toInt() : null;
                        final total =
                            totalTrials is num ? totalTrials.toInt() : null;
                        final percent = acc is num ? acc.toDouble() : null;
                        final overall = (correct != null &&
                                total != null &&
                                percent != null)
                            ? '$correct/$total (${percent.toStringAsFixed(1)}%)'
                            : '-';
                        return Text("Overall: $overall",
                            style:
                                const TextStyle(fontWeight: FontWeight.bold));
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Avg reaction time: ${behavioral['mean_reaction_ms'] ?? '-'} ms",
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    if (behavioral['omission_count'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        "Auto-submitted / timed out: ${behavioral['omission_count']}",
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Divider(color: Colors.white24, height: 1),
                    const SizedBox(height: 10),
                    const Text(
                      "Behavioral details",
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _rowLabelValue(
                      "Accuracy",
                      (analysis['behavioral_accuracy'] is num)
                          ? '${(analysis['behavioral_accuracy'] as num).toStringAsFixed(1)}%'
                          : '-',
                    ),
                    _rowLabelValue(
                      "RT score",
                      (analysis['behavioral_rt_score'] is num)
                          ? (analysis['behavioral_rt_score'] as num)
                              .toStringAsFixed(1)
                          : '-',
                    ),
                    _rowLabelValue(
                      "Consistency score",
                      (analysis['behavioral_consistency_score'] is num)
                          ? (analysis['behavioral_consistency_score'] as num).toStringAsFixed(1)
                          : '-',
                    ),
                    _rowLabelValue(
                      "Consistency bonus",
                      (analysis['behavioral_consistency_bonus'] is num)
                          ? '+${(analysis['behavioral_consistency_bonus'] as num).toStringAsFixed(2)}'
                          : '-',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      GamesHubScreen.routeName,
                      arguments: {
                        'recs': recs,
                        'gameLibraryTotal': gameLibraryTotal,
                        'recommendationNote': recommendationNote,
                      },
                    );
                  },
                  child: const Text("Open Practice Activities"),
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppDesign.surface,
        border: Border.all(color: Colors.white24.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(AppDesign.radiusM),
      ),
      child: child,
    );
  }

  Color _trendColor(dynamic valueOrTrend) {
    if (valueOrTrend is num) {
      final value = valueOrTrend.toDouble();
      if (value > 0) return const Color(0xFF38D27A);
      if (value < 0) return const Color(0xFFFF6B6B);
      return const Color(0xFFFFC857);
    }

    final trend = (valueOrTrend ?? '').toString().toLowerCase();
    if (trend == 'improved') return const Color(0xFF38D27A);
    if (trend == 'declined') return const Color(0xFFFF6B6B);
    return const Color(0xFFFFC857);
  }

  Widget _metricCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    String? subtitle,
    Color? color,
    double? scoreValue,
  }) {
    final accent = color ?? Theme.of(context).colorScheme.secondary;
    return Container(
      constraints: const BoxConstraints(minWidth: 155, maxWidth: 220),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.18),
            const Color(0xFF11141A),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const Spacer(),
              if (scoreValue != null) _statusChip(scoreValue, compact: true),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(double value, {bool compact = false}) {
    final color = _scoreColor(value);
    final label = value >= 75
        ? 'Good'
        : value >= 50
            ? 'Medium'
            : 'Needs improvement';
    final emoji = value >= 75
        ? '🟢'
        : value >= 50
            ? '🟡'
            : '🔴';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        compact ? emoji : '$emoji $label',
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _statBadge(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    final accent = color ?? Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 16),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _recommendationCard(Map rec) {
    final title = (rec['title'] ?? 'Recommended practice').toString();
    final description = (rec['description'] ?? '').toString();
    final games = (rec['games'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(description,
                  style: const TextStyle(color: Colors.white70, height: 1.35)),
            ],
            if (games.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...games.map(
                (game) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $game'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _breakdownRow(String label, dynamic value) {
    final v = value is num ? value.toDouble() : null;
    final text = v != null ? _formatMetricNum(v) : '-';
    final color = v != null ? _scoreColor(v) : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13.5, color: Colors.white70)),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                text,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              if (v != null) ...[
                const SizedBox(height: 4),
                _statusChip(v, compact: true),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _rowLabelValue(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13.5, color: Colors.white70)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF00E0C7),
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartDatum {
  final String label;
  final double value;
  final Color color;

  const _ChartDatum(this.label, this.value, this.color);
}

class _BarChartPainter extends CustomPainter {
  final List<_ChartDatum> items;

  _BarChartPainter(this.items);

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty) return;

    const topPad = 8.0;
    const bottomPad = 26.0;
    final chartHeight = size.height - topPad - bottomPad;
    final maxValue = items
        .map((e) => e.value)
        .fold<double>(100.0, (prev, e) => math.max(prev, e));
    final gridPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;

    for (int i = 0; i < 4; i++) {
      final y = topPad + chartHeight * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    const gap = 10.0;
    final barWidth = (size.width - gap * (items.length + 1)) / items.length;

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final normalized = (item.value / maxValue).clamp(0.0, 1.0).toDouble();
      final barHeight = chartHeight * normalized;
      final left = gap + i * (barWidth + gap);
      final rect = Rect.fromLTWH(
        left,
        topPad + chartHeight - barHeight,
        barWidth,
        barHeight,
      );
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [item.color.withValues(alpha: 0.45), item.color],
        ).createShader(rect);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        paint,
      );

      final valuePainter = TextPainter(
        text: TextSpan(
          text: item.value.toStringAsFixed(0),
          style: const TextStyle(fontSize: 10, color: Colors.white70),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: barWidth + 8);
      valuePainter.paint(
        canvas,
        Offset(left + (barWidth - valuePainter.width) / 2, rect.top - 14),
      );

      final labelPainter = TextPainter(
        text: TextSpan(
          text: item.label,
          style: const TextStyle(fontSize: 10, color: Colors.white70),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: barWidth + 12);
      labelPainter.paint(
        canvas,
        Offset(left + (barWidth - labelPainter.width) / 2, size.height - 18),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) => true;
}

class _RadarChartPainter extends CustomPainter {
  final List<_ChartDatum> items;

  _RadarChartPainter(this.items);

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2 + 6);
    final radius = math.min(size.width, size.height) / 2 - 34;
    final gridPaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;

    for (int level = 1; level <= 4; level++) {
      final factor = level / 4;
      final path = Path();
      for (int i = 0; i < items.length; i++) {
        final angle = -math.pi / 2 + (2 * math.pi * i / items.length);
        final point = Offset(
          center.dx + math.cos(angle) * radius * factor,
          center.dy + math.sin(angle) * radius * factor,
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    final fillPath = Path();
    for (int i = 0; i < items.length; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / items.length);
      final axisPoint = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawLine(center, axisPoint, axisPaint);

      final normalized = (items[i].value / 100).clamp(0.0, 1.0).toDouble();
      final point = Offset(
        center.dx + math.cos(angle) * radius * normalized,
        center.dy + math.sin(angle) * radius * normalized,
      );
      if (i == 0) {
        fillPath.moveTo(point.dx, point.dy);
      } else {
        fillPath.lineTo(point.dx, point.dy);
      }

      final labelPainter = TextPainter(
        text: TextSpan(
          text: items[i].label,
          style: const TextStyle(fontSize: 10, color: Colors.white70),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 64);
      final labelOffset = Offset(
        center.dx + math.cos(angle) * (radius + 10) - labelPainter.width / 2,
        center.dy + math.sin(angle) * (radius + 10) - labelPainter.height / 2,
      );
      labelPainter.paint(canvas, labelOffset);
    }
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..color = const Color(0xFF6EA8FF).withValues(alpha: 0.22)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = const Color(0xFF6EA8FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter oldDelegate) => true;
}

class _MiniTrendChartPainter extends CustomPainter {
  final List<double> scores;
  final List<String> labels;

  _MiniTrendChartPainter(this.scores, this.labels);

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.isEmpty) return;

    const topPad = 10.0;
    const bottomPad = 24.0;
    final chartHeight = size.height - topPad - bottomPad;
    final maxScore = scores.fold<double>(100.0, (prev, e) => math.max(prev, e));
    final minScore = scores.fold<double>(100.0, (prev, e) => math.min(prev, e));
    final yMin = math.max(0.0, minScore - 10);
    final yMax = math.max(100.0, maxScore + 5);
    final gridPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;

    for (int i = 0; i < 4; i++) {
      final y = topPad + chartHeight * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final dx = scores.length == 1 ? size.width / 2 : size.width / (scores.length - 1);
    final points = <Offset>[];
    for (int i = 0; i < scores.length; i++) {
      final x = scores.length == 1 ? dx : i * dx;
      final denominator = (yMax - yMin).abs() < 0.001 ? 1.0 : (yMax - yMin);
      final y = topPad + chartHeight - ((scores[i] - yMin) / denominator * chartHeight);
      points.add(Offset(x, y));
    }

    final areaPath = Path()..moveTo(points.first.dx, topPad + chartHeight);
    for (final point in points) {
      areaPath.lineTo(point.dx, point.dy);
    }
    areaPath.lineTo(points.last.dx, topPad + chartHeight);
    areaPath.close();
    canvas.drawPath(
      areaPath,
      Paint()
        ..color = const Color(0xFF6EA8FF).withValues(alpha: 0.14)
        ..style = PaintingStyle.fill,
    );

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = const Color(0xFF6EA8FF)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );

    final pointPaint = Paint()..color = const Color(0xFF38D27A);
    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 4, pointPaint);
      if (i < labels.length) {
        final tp = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: const TextStyle(fontSize: 10, color: Colors.white70),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 50);
        tp.paint(canvas, Offset(points[i].dx - tp.width / 2, size.height - 18));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MiniTrendChartPainter oldDelegate) => true;
}

class _BrainWavePainter extends CustomPainter {
  final double seed;
  static const double _sampleStep = 3;

  _BrainWavePainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final baseY = size.height / 2;
    final guidePaint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), guidePaint);

    final colors = <Color>[
      const Color(0xFF6EA8FF),
      const Color(0xFF9B8CFF),
      const Color(0xFF38D27A),
    ];

    for (int i = 0; i < colors.length; i++) {
      final amplitude = 10 + (seed * 12) + i * 4;
      final frequency = 1.8 + i * 0.6;
      final phase = i * 0.8;
      final path = Path();
      for (double x = 0; x <= size.width; x += _sampleStep) {
        final normalized = x / size.width;
        final y = baseY +
            math.sin((normalized * math.pi * 2 * frequency) + phase) * amplitude +
            math.sin((normalized * math.pi * 2 * (frequency * 2.2)) + phase) * 3;
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      if (size.width > 0) {
        const normalized = 1.0;
        final y = baseY +
            math.sin((normalized * math.pi * 2 * frequency) + phase) * amplitude +
            math.sin((normalized * math.pi * 2 * (frequency * 2.2)) + phase) * 3;
        path.lineTo(size.width, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[i].withValues(alpha: 0.9)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BrainWavePainter oldDelegate) =>
      oldDelegate.seed != seed;
}
