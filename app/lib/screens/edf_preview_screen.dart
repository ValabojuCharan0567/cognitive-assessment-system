import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';

class EdfPreviewScreen extends StatefulWidget {
  static const routeName = '/edf-preview';
  const EdfPreviewScreen({super.key});

  @override
  State<EdfPreviewScreen> createState() => _EdfPreviewScreenState();
}

class _EdfPreviewScreenState extends State<EdfPreviewScreen> {
  String? _fileName;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _features;

  Future<FilePickerResult?> _pickEegFile() async {
    try {
      final filtered = await FilePicker.pickFiles(
        type: kIsWeb ? FileType.custom : FileType.any,
        allowedExtensions: kIsWeb ? ['edf', 'csv'] : null,
        withData: true,
      );
      if (filtered != null && filtered.files.isNotEmpty) {
        return filtered;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<void> _pickAndPreviewFile() async {
    final result = await _pickEegFile();

    if (result != null && result.files.isNotEmpty) {
      final picked = result.files.single;
      final path = kIsWeb ? null : picked.path;
      final name = picked.name;
      final ext = (picked.extension ?? name.split('.').last).toLowerCase();

      if (ext != 'edf' && ext != 'csv') {
        setState(() {
          _error = 'Please select a valid .edf or .csv file.';
          _features = null;
        });
        return;
      }

      setState(() {
        _fileName = name;
        _loading = true;
        _error = null;
        _features = null;
      });

      try {
        final bytes = picked.bytes ??
            (!kIsWeb && path != null ? await File(path).readAsBytes() : null);
        if (bytes == null) {
          throw Exception('Could not read selected file bytes. Try picking a local file.');
        }
        final api = ApiService();

        final features = await api.analyzeEegFile(
          'preview',
          bytes,
          ext: ext,
        );

        if (!mounted) return;
        setState(() {
          _features = features;
          _loading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = 'Preview failed: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EEG File Preview')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Preview EEG Features',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loading ? null : _pickAndPreviewFile,
              icon: const Icon(Icons.file_open),
              label: const Text('Pick EEG File'),
            ),
            const SizedBox(height: 16),
            if (_fileName != null) ...[
              Text('Selected: $_fileName',
                  style: const TextStyle(fontStyle: FontStyle.italic)),
              const SizedBox(height: 16),
            ],
            if (_loading) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              const Text('Analyzing file...'),
            ],
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 16),
            ],
            if (_features != null) ...[
              const Text(
                'Extracted Features:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _features!.entries
                          .map((e) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(e.key,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500)),
                                    Text(_formatValue(e.value),
                                        style: const TextStyle(
                                            fontFamily: 'Courier', fontSize: 12)),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatValue(dynamic v) {
    if (v is double) {
      return v.toStringAsFixed(6);
    } else if (v is int) {
      return v.toString();
    } else {
      return v.toString();
    }
  }
}
