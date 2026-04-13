import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  /// Override with `--dart-define=API_BASE_URL=https://host/api`
  static const String _kBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  String get baseUrl => _kBaseUrl;

  // Example endpoint
  String get healthUrl => "$baseUrl/cloud/health";

  // Example GET request
  Future<void> checkHealth() async {
    final url = Uri.parse(healthUrl);

    try {
      final response = await http.get(url);

      debugPrint("🌐 BASE URL: $baseUrl");
      debugPrint("📡 Response: ${response.body}");

      if (response.statusCode == 200) {
        debugPrint("✅ Backend connected");
      } else {
        debugPrint("❌ Backend error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ Connection failed: $e");
    }
  }

  // Login with Google
  Future<Map<String, dynamic>> loginWithGoogle({
    required String? idToken,
    required String? accessToken,
  }) async {
    if (idToken == null && accessToken == null) {
      throw Exception('Failed to obtain Google authentication tokens. Please try again and ensure you grant the required permissions.');
    }
    
    final url = Uri.parse("$baseUrl/login/google");
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'id_token': idToken,
        'access_token': accessToken,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to login with Google: ${response.body}');
    }
  }

  // Create child
  Future<Map<String, dynamic>> createChild({
    required String parentEmail,
    required String name,
    required int age,
    required int difficulty,
    required String dob,
    required String gender,
  }) async {
    final url = Uri.parse("$baseUrl/child");
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'parent_email': parentEmail,
        'name': name,
        'age': age,
        'difficulty_level': difficulty,
        'dob': dob,
        'gender': gender,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create child: ${response.body}');
    }
  }

  // Start assessment
  Future<Map<String, dynamic>> startAssessment(
    String childId, {
    required String type,
    String? preReportId,
  }) async {
    final url = Uri.parse("$baseUrl/assessment/start");
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'child_id': childId,
        'type': type,
        'pre_report_id': preReportId,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to start assessment: ${response.body}');
    }
  }

  // Submit assessment
  Future<Map<String, dynamic>> submitAssessment({
    required String assessmentId,
    required Map<String, dynamic> eeg,
    required Map<String, dynamic> audio,
    required Map<String, dynamic> behavioral,
  }) async {
    final url = Uri.parse("$baseUrl/assessment/submit");
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'assessment_id': assessmentId,
        'eeg': eeg,
        'audio': audio,
        'behavioral': behavioral,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to submit assessment: ${response.body}');
    }
  }

  // Analyze audio
  Future<Map<String, dynamic>> analyzeAudio(
    String childId,
    List<int> bytes, {
    required String ext,
    Map<String, dynamic>? devicePreprocessing,
    String? requestId,
    dynamic cancelToken,
    Function(int, int)? onSendProgress,
  }) async {
    final url = Uri.parse("$baseUrl/audio/analyze");
    final base64Audio = base64Encode(bytes);
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'audio_base64': base64Audio,
        'audio_ext': ext,
        'device_preprocessing': devicePreprocessing,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to analyze audio: ${response.body}');
    }
  }

  // Analyze EEG
  Future<Map<String, dynamic>> analyzeEeg(
    String childId,
    String eegB64, {
    required String ext,
    Map<String, dynamic>? devicePreprocessing,
  }) async {
    final url = Uri.parse("$baseUrl/eeg/analyze");
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'eeg_base64': eegB64,
        'eeg_ext': ext,
        'device_preprocessing': devicePreprocessing,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to analyze EEG: ${response.body}');
    }
  }

  // Get children for parent
  Future<List<dynamic>> getChildrenForParent(String email) async {
    final url = Uri.parse("$baseUrl/children/by_parent/$email");
    final response = await http.get(url);

    if (response.statusCode == 200) {
      return List<dynamic>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to get children: ${response.body}');
    }
  }

  // Get reports
  Future<List<dynamic>> getReports(String childId) async {
    final url = Uri.parse("$baseUrl/reports/$childId");
    final response = await http.get(url);

    if (response.statusCode == 200) {
      return List<dynamic>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to get reports: ${response.body}');
    }
  }

  // Get progress history (legacy /api/progress endpoint)
  Future<List<dynamic>> getProgress(String childId) async {
    final url = Uri.parse("$baseUrl/progress/$childId");
    final response = await http.get(url);

    if (response.statusCode == 200) {
      return List<dynamic>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to get progress: ${response.body}');
    }
  }

  // Get post status
  Future<Map<String, dynamic>> getPostStatus(
    String childId, {
    String? preReportId,
  }) async {
    final queryParams = preReportId != null ? {'pre_report_id': preReportId} : <String, String>{};
    final url = Uri.parse("$baseUrl/assessment/post_status/$childId").replace(queryParameters: queryParams);
    final response = await http.get(url);

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to get post status: ${response.body}');
    }
  }
}