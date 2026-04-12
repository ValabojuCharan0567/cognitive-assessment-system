import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ProgressScreen extends StatefulWidget {
  static const routeName = '/progress';
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _error;
  List<dynamic> _history = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final childId = ModalRoute.of(context)!.settings.arguments as String;
    _load(childId);
  }

  Future<void> _load(String childId) async {
    try {
      final h = await _api.getProgress(childId);
      setState(() {
        _history = h;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Progress Tracking')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Text(_error!, style: const TextStyle(color: Colors.redAccent))
                : _history.isEmpty
                    ? const Text('No assessments yet.')
                    : ListView.builder(
                        itemCount: _history.length,
                        itemBuilder: (ctx, i) {
                          final a = _history[i] as Map<String, dynamic>;
                          final scores = (a['scores'] as Map?)?.cast<String, dynamic>() ?? {};
                          final created = (a['created_at'] as String?) ?? '';

                          double toD(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

                          return Card(
                            child: ListTile(
                              title: Text('Assessment #${i + 1}'),
                              subtitle: Text(
                                'Memory: ${toD(scores['memory']).toStringAsFixed(1)} | '
                                'Attention: ${toD(scores['attention']).toStringAsFixed(1)} | '
                                'Language: ${toD(scores['language']).toStringAsFixed(1)}\n'
                                'Date: $created',
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

