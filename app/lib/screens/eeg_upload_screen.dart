import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../theme/app_design.dart';
import 'audio_assessment_screen.dart';

Map<String, dynamic> _buildEegPayloadInBackground(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final ext = args['ext'] as String;
  final name = args['name'] as String;

  String readAscii(int start, int len) {
    if (start + len > bytes.length) return '';
    return ascii
        .decode(bytes.sublist(start, start + len), allowInvalid: true)
        .trim();
  }

  Map<String, dynamic> extractEdfHeader() {
    final headerBytes = int.tryParse(readAscii(184, 8)) ?? 0;
    final records = int.tryParse(readAscii(236, 8)) ?? -1;
    final recordDuration = double.tryParse(readAscii(244, 8)) ?? 0.0;
    final signals = int.tryParse(readAscii(252, 4)) ?? 0;
    final estimatedDuration =
        (records > 0 && recordDuration > 0) ? records * recordDuration : null;

    return {
      'header_bytes': headerBytes,
      'num_records': records,
      'record_duration_sec': recordDuration,
      'num_signals': signals,
      if (estimatedDuration != null)
        'estimated_duration_sec': estimatedDuration,
      'start_date': readAscii(168, 8),
      'start_time': readAscii(176, 8),
    };
  }

  final devicePreprocessing = <String, dynamic>{
    'pipeline_version': 'device-pre-v1',
    'modality': 'eeg',
    'file_name': name,
    'file_ext': ext,
    'file_size_bytes': bytes.length,
    'sha256': sha256.convert(bytes).toString(),
    'captured_at': DateTime.now().toUtc().toIso8601String(),
  };

  if (ext == 'edf') {
    devicePreprocessing['edf_header'] = extractEdfHeader();
  }

  return {
    'devicePreprocessing': devicePreprocessing,
  };
}

class EEGUploadScreen extends StatefulWidget {
  static const routeName = '/eeg-upload';
  const EEGUploadScreen({super.key});

  @override
  State<EEGUploadScreen> createState() => _EEGUploadScreenState();
}

class _EEGUploadScreenState extends State<EEGUploadScreen> {
  String? _fileName;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _eegFeatures;
  bool _isPickingFile = false;

  Future<FilePickerResult?> _pickEegFile() async {
    try {
      final filtered = await FilePicker.platform.pickFiles(
        type: kIsWeb ? FileType.custom : FileType.any,
        allowedExtensions: kIsWeb ? ['edf'] : null,
        withData: true,
      );
      if (filtered != null && filtered.files.isNotEmpty) {
        return filtered;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not open EEG file picker: $e';
        });
      }
      return null;
    }

    return null;
  }

  String _readChildId(Map<String, dynamic> child) {
    final dynamic id = child['id'] ?? child['childId'];
    return (id ?? '').toString();
  }

  Future<void> _pickFile(
    Map<String, dynamic> child, {
    String? assessmentType,
  }) async {
    if (_loading || _isPickingFile) return;
    final childId = _readChildId(child);
    if (childId.isEmpty) {
      setState(() {
        _error = 'Missing child id. Please go back and select child again.';
      });
      return;
    }
    if (mounted) {
      setState(() {
        _isPickingFile = true;
        _error = null;
      });
    }

    try {
      final result = await _pickEegFile();
      if (result == null || result.files.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'No file selected.';
          });
        }
        return;
      }

      final picked = result.files.single;
      final path = kIsWeb ? null : picked.path;
      final name = picked.name;
      final ext = (picked.extension ?? name.split('.').last).toLowerCase();
      if (ext != 'edf') {
        setState(() {
          _fileName = name;
          _error = 'Please select a valid .edf EEG file.';
          _loading = false;
        });
        return;
      }
      setState(() {
        _fileName = name;
        _loading = true;
        _error = null;
        _eegFeatures = null;
      });

      final bytes = picked.bytes ??
          (!kIsWeb && path != null ? await File(path).readAsBytes() : null);
      if (bytes == null) {
        throw Exception(
            'Could not read selected file bytes. Try picking a local file.');
      }
      final payload = await compute(_buildEegPayloadInBackground, {
        'bytes': bytes,
        'ext': ext,
        'name': name,
      });
      final devicePreprocessing =
          (payload['devicePreprocessing'] as Map).cast<String, dynamic>();
      final api = ApiService();
      final eegFeatures = await api.analyzeEegFile(
        childId,
        bytes,
        ext: ext,
        devicePreprocessing: devicePreprocessing,
      );
      if (!mounted) return;
      setState(() {
        _eegFeatures = eegFeatures;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'EEG analysis failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _isPickingFile = false;
        });
      }
    }
  }

  double? _numFrom(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v is num) return v.toDouble();
      if (v is String) {
        final p = double.tryParse(v);
        if (p != null) return p;
      }
    }
    return null;
  }

  String? _strFrom(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return null;
  }

  String _prettyLabel(String key) {
    const labels = {
      'load_level': 'Load level',
      'cognitive_load_level': 'Load level',
      'mental_effort_score': 'Effort',
      'effort': 'Effort',
      'frontal_asymmetry_index': 'Frontal asymmetry',
      'alpha_beta_ratio': 'Alpha / beta ratio',
      'theta_alpha_ratio': 'Theta / alpha ratio',
      'theta_beta_ratio': 'Theta / beta ratio',
      'signal_entropy': 'Signal entropy',
      'heart_rate_variability': 'Heart-rate variability',
      'confidence': 'Confidence',
    };
    final normalized = key.toLowerCase();
    if (labels.containsKey(normalized)) {
      return labels[normalized]!;
    }

    final text = key.replaceAll('_', ' ').trim();
    if (text.isEmpty) return key;
    return text[0].toUpperCase() + text.substring(1);
  }

  String _formatPercent01(double? value, {int decimals = 0}) {
    if (value == null || value.isNaN || value.isInfinite) return 'N/A';
    return '${(value * 100).toStringAsFixed(decimals)}%';
  }

  String _displayLoadLevel(String? loadLevel) {
    final normalized = (loadLevel ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return 'Medium';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  String _formatNumber(double n) {
    if (n.isNaN || n.isInfinite) return 'N/A';
    if (n == 0.0) return '0.0';
    final absValue = n.abs();

    // For very small numbers, use scientific notation
    if (absValue < 0.0001) {
      return n.toStringAsExponential(2);
    }
    // Standard fixed formatting
    if (absValue >= 100) return n.toStringAsFixed(1);
    if (absValue >= 10) return n.toStringAsFixed(2);
    return n.toStringAsFixed(3);
  }

  String _deriveLoadLevel(double? effort) {
    if (effort == null) return 'medium';
    if (effort < 0.35) return 'low';
    if (effort > 0.75) return 'high';
    return 'medium';
  }

  Widget _metricTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatFieldValue(String key, dynamic value) {
    if (value == null) return 'N/A';
    final normalizedKey = key.toLowerCase();
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is String && normalizedKey.contains('load_level')) {
      return _displayLoadLevel(value);
    }
    if (value is num) {
      final numValue = value.toDouble();
      if (normalizedKey.contains('sample_rate') ||
          normalizedKey.contains('hz') ||
          normalizedKey.contains('frequency')) {
        return '${_formatNumber(numValue)} Hz';
      }
      if (normalizedKey.contains('duration') ||
          normalizedKey.contains('time_sec')) {
        return '${_formatNumber(numValue)} sec';
      }
      if (normalizedKey.contains('size') || normalizedKey.contains('bytes')) {
        return '${(numValue / 1024).toStringAsFixed(1)} KB';
      }
      if (normalizedKey.contains('confidence') ||
          normalizedKey.contains('effort') ||
          normalizedKey.contains('ratio') ||
          normalizedKey.contains('percentage') ||
          normalizedKey.contains('probability')) {
        if (numValue >= 0.0 && numValue <= 1.0) {
          return '${(numValue * 100).toStringAsFixed(1)}%';
        }
      }
      return _formatNumber(numValue);
    }
    return value.toString();
  }

  Widget _buildTechnicalDetailsWidget(Map<String, dynamic> data,
      {String modality = 'eeg'}) {
    // Filter to show only meaningful fields
    final importantKeys = modality == 'eeg'
        ? [
            'alpha_power',
            'beta_power',
            'theta_power',
            'delta_power',
            'gamma_power',
            'alpha_beta_ratio',
            'mental_effort_score',
            'effort',
            'load_level',
            'cognitive_load_level',
            'signal_entropy',
            'entropy',
            'hjorth_activity',
            'hjorth_mobility',
            'hjorth_complexity',
            'frontal_asymmetry',
            'heart_rate_variability',
          ]
        : [
            'fluency_score',
            'fluency_label',
            'fluency_class',
            'label',
            'class',
            'prediction',
            'confidence',
            'duration_sec',
            'duration',
            'rms_energy',
            'energy',
            'sample_rate_hz',
            'sample_rate',
          ];

    // Build filtered entries while avoiding duplicate summary fields.
    final filteredEntries = <MapEntry<String, dynamic>>[];
    final seenCanonical = <String>{};
    for (final entry in data.entries) {
      final key = entry.key.toLowerCase();
      final isImportant =
          importantKeys.any((imp) => key.contains(imp.toLowerCase()));
      if (!isImportant || key.startsWith('_') || entry.value == null) {
        continue;
      }

      final canonicalKey = switch (key) {
        'mental_effort_score' || 'effort' => 'effort',
        'cognitive_load_level' || 'load_level' => 'load_level',
        'frontal_asymmetry_index' => 'frontal_asymmetry',
        _ => key,
      };
      if (seenCanonical.add(canonicalKey)) {
        filteredEntries.add(entry);
      }
    }

    // Group by category.
    final grouped = <String, List<MapEntry<String, dynamic>>>{
      'Summary': [],
      'Brain activity': [],
      'Advanced details': [],
    };

    for (final entry in filteredEntries) {
      final key = entry.key.toLowerCase();
      if (key.contains('load_level') ||
          key.contains('effort') ||
          key.contains('confidence')) {
        grouped['Summary']!.add(entry);
      } else if (key.contains('power') ||
          key.contains('alpha') ||
          key.contains('beta') ||
          key.contains('theta') ||
          key.contains('delta') ||
          key.contains('gamma')) {
        grouped['Brain activity']!.add(entry);
      } else {
        grouped['Advanced details']!.add(entry);
      }
    }

    final sections = <Widget>[];
    grouped.forEach((title, entries) {
      if (entries.isEmpty) return;

      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.cyanAccent,
            ),
          ),
        ),
      );

      for (final entry in entries) {
        sections.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  flex: 1,
                  child: Text(
                    _prettyLabel(entry.key),
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    _formatFieldValue(entry.key, entry.value),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    });

    if (sections.isEmpty) {
      sections.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'No additional technical details available',
            style: TextStyle(
                fontSize: 11,
                color: Colors.white70,
                fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }

  Widget _buildEegResult(Map<String, dynamic> data) {
    final effort = _numFrom(data, ['effort', 'mental_effort_score']);
    final confidence = _numFrom(data, ['confidence']);
    final rawLoadLevel =
        _strFrom(data, ['cognitive_load_level', 'load_level']) ??
            _deriveLoadLevel(effort);
    final loadLevel = _displayLoadLevel(rawLoadLevel);

    final cards = <Widget>[
      _metricTile('Load level', loadLevel),
      if (effort != null) _metricTile('Effort', _formatPercent01(effort)),
      if (confidence != null)
        _metricTile('Confidence', _formatPercent01(confidence)),
    ];

    final summaryText = [
      '$loadLevel cognitive load detected',
      if (effort != null) 'effort ${_formatPercent01(effort)}',
      if (confidence != null) 'confidence ${_formatPercent01(confidence)}',
    ].join(' • ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Result (EEG File)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: cards),
              const SizedBox(height: 10),
              Text(
                summaryText,
                style: const TextStyle(fontSize: 12.5, color: Colors.white70),
              ),
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('Technical details (advanced)',
                    style: TextStyle(fontSize: 13)),
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child:
                            _buildTechnicalDetailsWidget(data, modality: 'eeg'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final routeArgs = ModalRoute.of(context)!.settings.arguments;
    String childId;
    String? assessmentType;
    String? preReportId;
    Map<String, dynamic>? child;
    if (routeArgs is String) {
      childId = routeArgs;
    } else {
      final m = routeArgs as Map;
      childId = (m['childId'] ?? '').toString();
      assessmentType = m['assessmentType'] as String?;
      preReportId = m['preReportId']?.toString();
      if (m['child'] is Map) {
        child = (m['child'] as Map).cast<String, dynamic>();
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('EEG Upload')),
      body: SingleChildScrollView(
        padding: AppDesign.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Upload an EEG data file in `.edf` format.'),
            const SizedBox(height: 8),
            const Text(
              'If the file is not visible, browse to Downloads or Documents and select the `.edf` file.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 14),
            if (_fileName != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: Colors.greenAccent, size: 22),
                  const SizedBox(width: 8),
                  const Text('EEG file selected:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_fileName!,
                          style: const TextStyle(
                              fontSize: 14, fontStyle: FontStyle.italic))),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  border: Border.all(
                      color: AppDesign.primary.withValues(alpha: 0.45)),
                  borderRadius: BorderRadius.circular(AppDesign.radiusM),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Upload status: File uploaded',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Text('File type: EEG'),
                    Text('File name: $_fileName'),
                    if (_eegFeatures != null &&
                        _eegFeatures!['edf_header'] != null) ...[
                      const Divider(),
                      const Text('File Preview:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      ...(_eegFeatures!['edf_header'] as Map<String, dynamic>)
                          .entries
                          .map((e) => Text('${e.key}: ${e.value}',
                              style: const TextStyle(fontSize: 12))),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _loading
                  ? null
                  : () => _pickFile(
                        child ?? {'id': childId},
                        assessmentType: assessmentType,
                      ),
              child: const Text('Pick EEG File and Analyze'),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.08),
                  border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.55)),
                  borderRadius: BorderRadius.circular(AppDesign.radiusM),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Error',
                            style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _error!));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Error copied to clipboard')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy'),
                        ),
                      ],
                    ),
                    SelectableText(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
            ],
            if (_eegFeatures != null) ...[
              const SizedBox(height: 14),
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: _buildEegResult(_eegFeatures!),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.pushNamed(
                            context,
                            AudioAssessmentScreen.routeName,
                            arguments: {
                              'child': child,
                              // Guarantee string ID in downstream route
                              'childId': childId.toString(),
                              'eegFeatures': _eegFeatures,
                              if (assessmentType != null)
                                'assessmentType': assessmentType,
                              if (preReportId != null && preReportId.isNotEmpty)
                                'preReportId': preReportId,
                            },
                          ),
                  child: const Text('Continue to Audio Assessment'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
