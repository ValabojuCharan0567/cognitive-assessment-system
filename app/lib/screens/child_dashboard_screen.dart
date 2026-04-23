import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/google_sign_in_service.dart';
import '../services/session_service.dart';
import '../theme/app_design.dart';
import 'auth_screen.dart';
import 'eeg_upload_screen.dart';
import 'results_screen.dart';

class ChildDashboardScreen extends StatefulWidget {
  static const routeName = '/child-dashboard';
  const ChildDashboardScreen({super.key});

  @override
  State<ChildDashboardScreen> createState() => _ChildDashboardScreenState();
}

class _ChildDashboardScreenState extends State<ChildDashboardScreen> {
  final _api = ApiService();
  final _session = SessionService();
  bool _loadingReports = true;
  String? _error;
  List<dynamic> _reports = [];
  String? _childId;

  Map<String, dynamic>? get _childFromArgs {
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  Map<String, dynamic> _safeMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  DateTime? _parseDate(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  String _prettyDate(dynamic value) {
    final dt = _parseDate(value);
    if (dt == null) return 'Saved report';
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$day/$month/${dt.year}';
  }

  /// Date + time for report titles (e.g. 13/04/2026 14:30).
  String _prettyDateTime(dynamic value) {
    final dt = _parseDate(value);
    if (dt == null) return '';
    final d = _prettyDate(value);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$d $h:$m';
  }

  /// Newest activity time for this cycle (for sorting).
  DateTime _cycleLatestTimestamp(Map<String, Map<String, dynamic>?> cycle) {
    DateTime? latest;
    for (final r in [cycle['pre'], cycle['post']]) {
      if (r == null) continue;
      final t = _parseDate(r['created_at']);
      if (t != null && (latest == null || t.isAfter(latest))) {
        latest = t;
      }
    }
    return latest ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Title from dates only — no "Report 1 / 2".
  String _reportCycleHeading(Map<String, Map<String, dynamic>?> cycle) {
    final pre = cycle['pre'];
    final post = cycle['post'];
    final preWhen = pre != null ? _prettyDateTime(pre['created_at']) : '';
    final postWhen = post != null ? _prettyDateTime(post['created_at']) : '';
    if (pre != null && post != null) {
      final w = preWhen.isNotEmpty ? preWhen : postWhen;
      return w.isNotEmpty ? 'Assessment · $w' : 'Assessment';
    }
    if (pre != null) {
      return preWhen.isNotEmpty ? 'Pre-assessment · $preWhen' : 'Pre-assessment';
    }
    if (post != null) {
      return postWhen.isNotEmpty
          ? 'Post-assessment · $postWhen'
          : 'Post-assessment';
    }
    return 'Assessment';
  }

  int _compareCreated(Map<String, dynamic> a, Map<String, dynamic> b) {
    final da =
        _parseDate(a['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final db =
        _parseDate(b['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return da.compareTo(db);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final child = _childFromArgs;
    final childId = (child?['id'] ?? '').toString();
    if (childId.isNotEmpty && (_childId != childId || _reports.isEmpty)) {
      _childId = childId;
      _loadReports(childId);
    }
  }

  Future<void> _loadReports(String childId) async {
    setState(() {
      _loadingReports = true;
    });

    try {
      final reports = await _api.getReports(childId);
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingReports = false);
      }
    }
  }

  /// Pair each saved pre-test with its linked post-test.
  List<Map<String, Map<String, dynamic>?>> _buildReportCycles() {
    final allReports = _reports
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final preReports = allReports
        .where((r) => (r['type'] ?? '').toString().toLowerCase() == 'pre')
        .toList()
      ..sort(_compareCreated);
    final postReports = allReports
        .where((r) => (r['type'] ?? '').toString().toLowerCase() == 'post')
        .toList()
      ..sort(_compareCreated);

    final postByPreId = <String, Map<String, dynamic>>{};
    final unmatchedPosts = <Map<String, dynamic>>[];
    for (final post in postReports) {
      final linkedId = (post['linked_pre_report_id'] ?? '').toString();
      if (linkedId.isNotEmpty) {
        postByPreId[linkedId] = post;
      } else {
        unmatchedPosts.add(post);
      }
    }

    final cycles = <Map<String, Map<String, dynamic>?>>[];
    for (final pre in preReports) {
      final preId = (pre['id'] ?? '').toString();
      Map<String, dynamic>? matchedPost = postByPreId.remove(preId);
      if (matchedPost == null && unmatchedPosts.isNotEmpty) {
        matchedPost = unmatchedPosts.removeAt(0);
      }
      cycles.add({'pre': pre, 'post': matchedPost});
    }

    for (final post in postByPreId.values) {
      cycles.add({'pre': null, 'post': post});
    }
    for (final post in unmatchedPosts) {
      cycles.add({'pre': null, 'post': post});
    }

    cycles.sort(
      (a, b) => _cycleLatestTimestamp(b).compareTo(_cycleLatestTimestamp(a)),
    );
    return cycles;
  }

  Widget _childDetailsCard(Map<String, dynamic> child) {
    final name = child['name'] ?? 'Child';
    final age = child['age']?.toString() ?? '-';
    final gender = child['gender']?.toString();
    final dob = child['dob']?.toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$name',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Age: $age'),
            if (gender != null && gender.isNotEmpty) Text('Gender: $gender'),
            if (dob != null && dob.isNotEmpty) Text('DOB: $dob'),
          ],
        ),
      ),
    );
  }

  Future<void> _openReport(
      Map<String, dynamic> child, Map<String, dynamic> report) async {
    final scores = _safeMap(report['scores']);
    final recs = (report['recommendations'] as List<dynamic>?) ?? const [];
    final summary = report['summary'] as String?;

    await Navigator.pushNamed(
      context,
      ResultsScreen.routeName,
      arguments: {
        'child': child,
        'scores': scores,
        'recs': recs,
        'summary': summary,
        'analysis': _safeMap(report['analysis']),
        'behavioral': _safeMap(report['behavioral']),
        'comparison': _safeMap(report['comparison']),
        'deltas': _safeMap(report['deltas']),
        'trends': _safeMap(report['trends']),
        'history': _reports,
        'game_library_total': report['game_library_total'],
        'recommendation_note': (report['recommendation_note'] ?? '').toString(),
        'weak_areas_detected': report['weak_areas_detected'],
        'recommendation_logic': _safeMap(report['recommendation_logic']),
        'type': report['type'],
        'created_at': report['created_at'],
        'parentEmail': child['parent_email'],
      },
    );

    if (mounted && _childId != null) {
      await _loadReports(_childId!);
    }
  }

  Future<void> _startAssessment(Map<String, dynamic> child) async {
    await Navigator.pushNamed(
      context,
      EEGUploadScreen.routeName,
      arguments: {
        'child': child,
        'childId': child['id'],
        'assessmentType': 'initial',
      },
    );

    final childId = (child['id'] ?? '').toString();
    if (mounted && childId.isNotEmpty) {
      await _loadReports(childId);
    }
  }

  Future<void> _startPostAssessment(
    Map<String, dynamic> child, {
    String? preReportId,
  }) async {
    final childId = (child['id'] ?? '').toString();
    if (childId.isEmpty) return;

    try {
      final status =
          await _api.getPostStatus(childId, preReportId: preReportId);
      final s = (status['status'] ?? 'unknown').toString();
      if (s == 'locked' || s == 'no_pre' || s == 'completed') {
        final msg = status['message'] as String? ??
            'Post assessment is not available yet.';
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      if (!mounted) return;
      await Navigator.pushNamed(
        context,
        EEGUploadScreen.routeName,
        arguments: {
          'child': child,
          'childId': childId,
          'assessmentType': 'post',
          if (preReportId != null && preReportId.isNotEmpty)
            'preReportId': preReportId,
        },
      );

      if (mounted) {
        await _loadReports(childId);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start post assessment: $e')),
      );
    }
  }

  Future<void> _logout() async {
    try {
      await GoogleSignInService.signOut();
    } catch (_) {}
    await _session.clearSession();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AuthScreen.routeName,
      (route) => false,
    );
  }

  Widget _scoreChip(String label, dynamic value) {
    final score = _toDouble(value);
    final text = score == null ? '-' : score.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppDesign.radiusM),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
          const SizedBox(height: 2),
          Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _flowStateCard({
    required String title,
    required String status,
    required String subtitle,
    required Color color,
    required IconData icon,
    String? actionLabel,
    VoidCallback? onPressed,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppDesign.radiusM),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onPressed,
                child: Text(actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deltaChip(String label, dynamic deltaValue, dynamic trendValue) {
    final delta = _toDouble(deltaValue) ?? 0.0;
    final trend = (trendValue ?? '').toString().toLowerCase();
    final isPositive = trend == 'improved' || delta > 0;
    final color = trend == 'declined'
        ? Colors.redAccent
        : (isPositive ? Colors.greenAccent : Colors.orangeAccent);
    final sign = delta > 0 ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDesign.radiusM),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$label: $sign${delta.toStringAsFixed(1)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildReportSummary({
    required Map<String, dynamic> child,
    required Map<String, dynamic> report,
    required String title,
    required Color accent,
  }) {
    final scores = _safeMap(report['scores']);
    final analysis = _safeMap(report['analysis']);
    final deltas = _safeMap(report['deltas']);
    final trends = _safeMap(report['trends']);
    final summary = (report['summary'] ?? '').toString();
    final cognitive = _toDouble(
      scores['cognitive'] ??
          scores['overall_cognitive'] ??
          analysis['cognitive_score'],
    );
    final reportWhen = _prettyDateTime(report['created_at']);
    final headline =
        reportWhen.isEmpty ? title : '$title ($reportWhen)';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(AppDesign.radiusM),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: TextStyle(fontWeight: FontWeight.bold, color: accent),
          ),
          const SizedBox(height: 8),
          if (cognitive != null)
            Text(
              'Overall cognitive score: ${cognitive.toStringAsFixed(1)}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _scoreChip('Memory', scores['memory']),
              _scoreChip('Attention', scores['attention']),
              _scoreChip('Language', scores['language']),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(summary, maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
          if (deltas.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Change from linked pre-test',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _deltaChip('Memory', deltas['memory'], trends['memory']),
                _deltaChip(
                    'Attention', deltas['attention'], trends['attention']),
                _deltaChip('Language', deltas['language'], trends['language']),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _openReport(child, report),
              icon: const Icon(Icons.description_outlined),
              label: const Text('View Full Report'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCard(Map<String, dynamic> post) {
    final comparison = _safeMap(post['comparison']);
    final deltas = _safeMap(post['deltas']);
    final trends = _safeMap(post['trends']);
    final averageChange = _toDouble(comparison['average_change']);
    final summary = (comparison['summary'] ?? '').toString();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(AppDesign.radiusM),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Final Comparison',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purpleAccent),
          ),
          if (averageChange != null) ...[
            const SizedBox(height: 6),
            Text(
              'Average change: ${averageChange >= 0 ? '+' : ''}${averageChange.toStringAsFixed(1)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(summary, style: const TextStyle(color: Colors.white70)),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _deltaChip('Memory', deltas['memory'], trends['memory']),
              _deltaChip('Attention', deltas['attention'], trends['attention']),
              _deltaChip('Language', deltas['language'], trends['language']),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCycleCard(
    Map<String, dynamic> child,
    Map<String, Map<String, dynamic>?> cycle,
  ) {
    final pre = cycle['pre'];
    final post = cycle['post'];
    final preId = (pre?['id'] ?? '').toString();
    final postId = (post?['id'] ?? '').toString();
    final hasPre = pre != null;
    final hasPost = post != null;
    final finalUnlocked = hasPre && hasPost;

    return Card(
      key: ValueKey('cycle_${preId}_$postId'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _reportCycleHeading(cycle),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              pre != null
                  ? 'Each pre-test is auto-saved here, and it can have its own linked post-test.'
                  : 'This post-test was saved without an older linked pre-test.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _flowStateCard(
                  title: 'Pre-Test',
                  status: hasPre ? 'Saved automatically' : 'Pending',
                  subtitle: hasPre
                      ? 'Open the saved pre-test report anytime.'
                      : 'Complete a pre-test to generate a saved report.',
                  color: const Color(0xFF00E0C7),
                  icon: Icons.assignment_turned_in_outlined,
                  actionLabel: hasPre ? 'View' : 'Waiting',
                  onPressed: hasPre ? () => _openReport(child, pre) : null,
                ),
                _flowStateCard(
                  title: 'Post-Test',
                  status: hasPost
                      ? 'Completed'
                      : hasPre
                          ? 'Enabled'
                          : 'Locked',
                  subtitle: hasPost
                      ? 'The linked post-test has been completed.'
                      : hasPre
                          ? 'You can start the post-test for this saved pre-test.'
                          : 'Post-test is enabled only after a pre-test is saved.',
                  color: hasPost
                      ? Colors.orangeAccent
                      : hasPre
                          ? Colors.greenAccent
                          : Colors.white54,
                  icon: Icons.play_circle_outline,
                  actionLabel: hasPost
                      ? 'View'
                      : hasPre
                          ? 'Enable / Start'
                          : 'Locked',
                  onPressed: hasPost
                      ? () => _openReport(child, post)
                      : hasPre
                          ? () => _startPostAssessment(child, preReportId: preId)
                          : null,
                ),
                _flowStateCard(
                  title: 'Final Report',
                  status: finalUnlocked ? 'Unlocked' : 'Locked',
                  subtitle: finalUnlocked
                      ? 'The final comparison report is ready to view.'
                      : 'Final report unlocks after the post-test is completed.',
                  color:
                      finalUnlocked ? Colors.purpleAccent : Colors.white54,
                  icon: Icons.insights_outlined,
                  actionLabel:
                      finalUnlocked ? 'View Final Report' : 'Unlock after post-test',
                  onPressed: finalUnlocked ? () => _openReport(child, post) : null,
                ),
              ],
            ),
            if (pre != null)
              _buildReportSummary(
                child: child,
                report: pre,
                title: 'Pre-Test Report',
                accent: const Color(0xFF00E0C7),
              ),
            if (pre != null && post == null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () =>
                        _startPostAssessment(child, preReportId: preId),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Post-Test'),
                  ),
                  const Text(
                      'This button is linked to this saved report only.'),
                ],
              ),
            ],
            if (post != null)
              _buildReportSummary(
                child: child,
                report: post,
                title: 'Post-Test Report',
                accent: Colors.orangeAccent,
              ),
            if (pre != null && post != null) _buildComparisonCard(post),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = _childFromArgs;
    final fallbackChild = <String, dynamic>{'id': _childId ?? ''};
    final cycles = _buildReportCycles();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Child Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sign out — start fresh',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (_childId != null && _childId!.isNotEmpty) {
            await _loadReports(_childId!);
          }
        },
        child: ListView(
          padding: AppDesign.pagePadding,
          children: [
            if (child != null) _childDetailsCard(child),
            const SizedBox(height: 16),
            if (child != null)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed:
                        _loadingReports ? null : () => _startAssessment(child),
                    icon: const Icon(Icons.assignment_outlined),
                    label: const Text('Start Pre-Test'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loadingReports || _childId == null
                        ? null
                        : () => _loadReports(_childId!),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            if (_loadingReports)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_loadingReports && _error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              ),
            const Text(
              'Assessment Reports',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Newest at the top.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 12),
            if (!_loadingReports && cycles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No assessment reports yet for this child.',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ...cycles.map(
              (c) => _buildCycleCard(child ?? fallbackChild, c),
            ),
          ],
        ),
      ),
    );
  }
}

