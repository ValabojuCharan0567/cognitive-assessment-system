import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  /// Override with `--dart-define=API_BASE_URL=https://host/api`
  static const String _kBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  /// Large JSON + ML on the server (e.g. `/audio/analyze`) can take minutes.
  static const Duration _heavyRequestTimeout = Duration(seconds: 300);
  static const Duration _healthCheckTimeout = Duration(seconds: 6);
  final Dio _dio = Dio();

  String get baseUrl => _kBaseUrl;

  String _requestId(String prefix, [String? provided]) {
    final value = (provided ?? '').trim();
    if (value.isNotEmpty) return value;
    final ts = DateTime.now().toUtc().microsecondsSinceEpoch;
    return '$prefix-$ts';
  }

  Future<http.Response> _postJsonLong(
    Uri url,
    Map<String, dynamic> body,
    String requestId,
  ) {
    return http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'X-Request-ID': requestId,
          },
          body: jsonEncode(body),
        )
        .timeout(
          _heavyRequestTimeout,
          onTimeout: () {
            throw Exception(
              'Request timed out after ${_heavyRequestTimeout.inMinutes} minutes. '
              'Try a shorter recording, check $baseUrl/cloud/ready in a browser, '
              'or retry if the host was cold-starting.',
            );
          },
        );
  }

  // Example endpoint
  String get healthUrl => "$baseUrl/cloud/health";

  // Example GET request
  Future<void> checkHealth() async {
    final url = Uri.parse(healthUrl);

    try {
      final response = await http
          .get(url)
          .timeout(_healthCheckTimeout, onTimeout: () {
        throw Exception('Health check timed out after ${_healthCheckTimeout.inSeconds}s');
      });

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
    String? requestId,
  }) async {
    final url = Uri.parse("$baseUrl/assessment/submit");
    final reqId = _requestId('submit', requestId);
    final response = await _postJsonLong(url, {
      'assessment_id': assessmentId,
      'eeg': eeg,
      'audio': audio,
      'behavioral': behavioral,
    }, reqId);

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
    final reqId = _requestId('audio-$childId', requestId);
    
    // 🔥 Wake server before heavy request (prevents cold start abort)
    try {
      await checkHealth();
    } catch (e) {
      debugPrint('⚠️ Health check failed, proceeding anyway: $e');
    }
    
    final url = '$baseUrl/audio/analyze';
    final formData = FormData.fromMap({
      'child_id': childId,
      'audio_ext': ext,
      if (devicePreprocessing != null)
        'device_preprocessing': jsonEncode(devicePreprocessing),
      'audio': MultipartFile.fromBytes(bytes, filename: 'upload.$ext'),
    });

    final response = await _dio.post(
      url,
      data: formData,
      cancelToken: cancelToken is CancelToken ? cancelToken : null,
      onSendProgress: onSendProgress,
      options: Options(
        headers: {
          'X-Request-ID': reqId,
        },
        sendTimeout: _heavyRequestTimeout,
        receiveTimeout: _heavyRequestTimeout,
        validateStatus: (_) => true,
      ),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Map<String, dynamic>.from(response.data as Map);
    }

    final statusCode = response.statusCode ?? 0;
    final statusMessage = response.statusMessage?.trim();
    var message = 'Server error';

    if (response.data is Map<String, dynamic>) {
      final data = response.data as Map<String, dynamic>;
      message = data['message']?.toString() ??
          data['error']?.toString() ??
          message;
    } else if (response.data is String && response.data.toString().trim().isNotEmpty) {
      message = response.data.toString().trim();
    } else if (statusMessage?.isNotEmpty == true) {
      message = statusMessage!;
    }

    if (statusCode == 502) {
      message = 'Server temporarily unavailable. Please try again in a moment.';
    }

    throw Exception('Audio analysis failed ($statusCode): $message');
  }

  // Analyze EEG
  Future<Map<String, dynamic>> analyzeEegFile(
    String childId,
    List<int> bytes, {
    required String ext,
    Map<String, dynamic>? devicePreprocessing,
    String? requestId,
  }) async {
    final uri = Uri.parse("$baseUrl/eeg/analyze");
    final reqId = _requestId('eeg-$childId', requestId);

    final req = http.MultipartRequest('POST', uri);
    req.headers['X-Request-ID'] = reqId;
    req.fields['child_id'] = childId;
    req.fields['eeg_ext'] = ext;
    if (devicePreprocessing != null) {
      req.fields['device_preprocessing'] = jsonEncode(devicePreprocessing);
    }
    req.files.add(
      http.MultipartFile.fromBytes(
        'eeg',
        bytes,
        filename: 'upload.$ext',
      ),
    );

    final streamed = await req.send().timeout(
      _heavyRequestTimeout,
      onTimeout: () {
        throw Exception(
          'Request timed out after ${_heavyRequestTimeout.inMinutes} minutes. '
          'Try a shorter recording or retry if the host was cold-starting.',
        );
      },
    );
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    }
    throw Exception('Failed to analyze EEG: ${response.body}');
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