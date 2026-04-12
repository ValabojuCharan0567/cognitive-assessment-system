import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportExportService {
  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Filesystem-safe stamp from ISO datetime (e.g. 20260413_1430).
  String _dateTimeStampForFile(String createdAt) {
    if (createdAt.isEmpty) return 'latest';
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) {
      return createdAt.split('T').first.replaceAll('-', '');
    }
    final d =
        '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';
    final t =
        '${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}';
    return '${d}_$t';
  }

  String _text(dynamic value, {String fallback = '-'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _formatNumber(dynamic value, {int fractionDigits = 1}) {
    final number = _asDouble(value);
    if (number == null) return '-';
    return number.toStringAsFixed(fractionDigits);
  }

  String _reportFileName({
    required String reportType,
    required Map<String, dynamic>? child,
    required String createdAt,
  }) {
    final childName = _text(child?['name'], fallback: 'child')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final type = _text(reportType, fallback: 'report')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final stamp = _dateTimeStampForFile(createdAt);
    return '${childName.isEmpty ? 'child' : childName}_${type}_$stamp.pdf';
  }

  Future<void> previewReportPdf({
    required Map<String, dynamic>? child,
    required String reportType,
    required String createdAt,
    required String summary,
    required Map<String, dynamic> scores,
    required Map<String, dynamic> analysis,
    required Map<String, dynamic> behavioral,
    required Map<String, dynamic> comparison,
    required List<dynamic> recommendations,
  }) async {
    final bytes = await _buildPdfBytes(
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

    await Printing.layoutPdf(
      name: _reportFileName(
        reportType: reportType,
        child: child,
        createdAt: createdAt,
      ),
      onLayout: (_) async => bytes,
    );
  }

  Future<void> shareReportPdf({
    required Map<String, dynamic>? child,
    required String reportType,
    required String createdAt,
    required String summary,
    required Map<String, dynamic> scores,
    required Map<String, dynamic> analysis,
    required Map<String, dynamic> behavioral,
    required Map<String, dynamic> comparison,
    required List<dynamic> recommendations,
  }) async {
    final bytes = await _buildPdfBytes(
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

    await Printing.sharePdf(
      bytes: bytes,
      filename: _reportFileName(
        reportType: reportType,
        child: child,
        createdAt: createdAt,
      ),
    );
  }

  Future<Uint8List> _buildPdfBytes({
    required Map<String, dynamic>? child,
    required String reportType,
    required String createdAt,
    required String summary,
    required Map<String, dynamic> scores,
    required Map<String, dynamic> analysis,
    required Map<String, dynamic> behavioral,
    required Map<String, dynamic> comparison,
    required List<dynamic> recommendations,
  }) async {
    final doc = pw.Document(title: 'Cognitive Assessment Report');

    final childName = _text(child?['name'], fallback: 'Child');
    final childAge = _text(child?['age']);
    final savedDate = createdAt.isNotEmpty ? createdAt.split('T').first : '-';
    final cognitiveScore = _formatNumber(
      scores['overall_cognitive'] ?? scores['cognitive'] ?? analysis['cognitive_score'],
    );

    pw.Widget kvRow(String label, String value, {bool highlight = false}) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          color: highlight ? PdfColors.teal50 : PdfColors.grey100,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      );
    }

    pw.Widget sectionTitle(String title) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10, bottom: 6),
        child: pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.teal700,
          ),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            'Cognitive Assessment Report',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.teal800,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Child: $childName'),
          pw.Text('Age: $childAge'),
          pw.Text('Report type: ${_text(reportType, fallback: 'pre')}'),
          pw.Text('Saved on: $savedDate'),
          pw.SizedBox(height: 12),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.teal50,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Overall cognitive score: $cognitiveScore',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(_text(summary)),
              ],
            ),
          ),
          sectionTitle('Score breakdown'),
          kvRow('Memory', _formatNumber(scores['memory'])),
          kvRow('Attention', _formatNumber(scores['attention'])),
          kvRow('Language', _formatNumber(scores['language'])),
          kvRow('Behavioral', _formatNumber(analysis['behavioral_score'])),
          kvRow('EEG', _formatNumber(analysis['eeg_score'])),
          kvRow('Audio', _formatNumber(analysis['audio_score'])),
          sectionTitle('AI / fusion details'),
          kvRow('Efficiency', _text(analysis['cognitive_efficiency'])),
          kvRow(
            'Weights (B / E / A)',
            analysis['fusion_weights'] is Map
                ? () {
                    final w = Map<String, dynamic>.from(analysis['fusion_weights'] as Map);
                    return 'B:${_text(w['behavioral'])}  E:${_text(w['eeg'])}  A:${_text(w['audio'])}';
                  }()
                : '-',
          ),
          kvRow(
            'EEG confidence',
            analysis['eeg'] is Map
                ? '${((_asDouble((analysis['eeg'] as Map)['confidence']) ?? 0) * 100).toStringAsFixed(0)}%'
                : '-',
          ),
          sectionTitle('Behavioral details'),
          kvRow('Accuracy', '${_formatNumber(behavioral['accuracy_percent'])}%'),
          kvRow('Average RT', '${_formatNumber(behavioral['mean_reaction_ms'], fractionDigits: 0)} ms'),
          kvRow('RT score', _formatNumber(analysis['behavioral_rt_score'])),
          kvRow('Consistency bonus', _formatNumber(analysis['behavioral_consistency_bonus'], fractionDigits: 2)),
          if (comparison.isNotEmpty) ...[
            sectionTitle('Final comparison'),
            kvRow('Summary', _text(comparison['summary']), highlight: true),
            kvRow('Average change', _formatNumber(comparison['average_change'])),
          ],
          if (recommendations.isNotEmpty) ...[
            sectionTitle('Recommended practice'),
            ...recommendations.whereType<Map>().map((item) {
              final data = Map<String, dynamic>.from(item);
              final title = _text(data['title'], fallback: 'Recommended activity');
              final description = _text(data['description'], fallback: '');
              final games = (data['games'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 8),
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    if (description.isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(description),
                    ],
                    if (games.isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      ...games.map((game) => pw.Bullet(text: game)),
                    ],
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );

    return doc.save();
  }
}
