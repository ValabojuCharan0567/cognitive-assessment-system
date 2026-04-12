class AssessmentSession {
  final String id;
  final String childId;
  final String status;
  final String preReportId;
  final Map<String, dynamic> raw;

  const AssessmentSession({
    required this.id,
    required this.childId,
    required this.status,
    required this.preReportId,
    required this.raw,
  });

  factory AssessmentSession.fromJson(Map<String, dynamic> json) {
    return AssessmentSession(
      id: (json['id'] ?? '').toString(),
      childId: (json['child_id'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      preReportId: (json['pre_report_id'] ?? '').toString(),
      raw: Map<String, dynamic>.from(json),
    );
  }
}

class AudioAnalysis {
  final double? fluencyScore;
  final String fluencyLabel;
  final double? confidence;
  final bool valid;
  final bool silenceDetected;
  final double? speechRatio;
  final bool lowConfidence;
  final String? warning;
  final Map<String, dynamic> raw;

  const AudioAnalysis({
    required this.fluencyScore,
    required this.fluencyLabel,
    required this.confidence,
    required this.valid,
    required this.silenceDetected,
    required this.speechRatio,
    required this.lowConfidence,
    required this.warning,
    required this.raw,
  });

  factory AudioAnalysis.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    return AudioAnalysis(
      fluencyScore: asDouble(json['fluency_score']),
      fluencyLabel: (json['fluency_label'] ?? '').toString(),
      confidence: asDouble(json['confidence']),
      valid: json['valid'] != false,
      silenceDetected: json['silence_detected'] == true,
      speechRatio: asDouble(json['speech_ratio']),
      lowConfidence: json['low_confidence'] == true,
      warning: json['warning']?.toString(),
      raw: Map<String, dynamic>.from(json),
    );
  }

  bool get canSubmit => valid && !silenceDetected && fluencyScore != null;

  Map<String, dynamic> toAssessmentPayload() {
    return {
      'fluency_score': fluencyScore,
      'fluency_label': fluencyLabel,
      if (confidence != null) 'confidence': confidence,
      'valid': valid,
      'silence_detected': silenceDetected,
      if (speechRatio != null) 'speech_ratio': speechRatio,
      'low_confidence': lowConfidence,
      if (warning != null && warning!.trim().isNotEmpty) 'warning': warning,
    };
  }
}

class AssessmentResult {
  final Map<String, dynamic> scores;
  final List<dynamic> recommendations;
  final String summary;
  final Map<String, dynamic> analysis;
  final Map<String, dynamic> behavioral;
  final Map<String, dynamic> raw;

  const AssessmentResult({
    required this.scores,
    required this.recommendations,
    required this.summary,
    required this.analysis,
    required this.behavioral,
    required this.raw,
  });

  factory AssessmentResult.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return <String, dynamic>{};
    }

    return AssessmentResult(
      scores: asMap(json['scores']),
      recommendations: (json['recommendations'] as List?)?.toList() ?? const [],
      summary: (json['summary'] ?? '').toString(),
      analysis: asMap(json['analysis']),
      behavioral: asMap(json['behavioral']),
      raw: Map<String, dynamic>.from(json),
    );
  }

  Map<String, dynamic> toRouteArguments({
    required String childId,
    Map<String, dynamic>? child,
    AudioAnalysis? audioAnalysis,
  }) {
    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return <String, dynamic>{};
    }

    return {
      if (child != null) 'child': child,
      'childId': childId,
      'scores': scores,
      'recs': recommendations,
      'summary': summary,
      'analysis': analysis,
      'behavioral': behavioral,
      'comparison': asMap(raw['comparison']),
      'trends': asMap(raw['trends']),
      'deltas': asMap(raw['deltas']),
      'type': (raw['report_type'] ?? raw['type'] ?? '').toString(),
      'created_at': (raw['created_at'] ?? '').toString(),
      'report_id': (raw['report_id'] ?? '').toString(),
      'game_library_total': raw['game_library_total'],
      'recommendation_note': (raw['recommendation_note'] ?? '').toString(),
      'weak_areas_detected': raw['weak_areas_detected'],
      'recommendation_logic': asMap(raw['recommendation_logic']),
      if (audioAnalysis != null) 'audioAnalysis': audioAnalysis.raw,
    };
  }
}
