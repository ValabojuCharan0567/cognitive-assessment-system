import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File;
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/audio_service_mobile.dart'
    if (dart.library.html) '../services/audio_service_web.dart';

import '../services/audio_compressor.dart';
import '../services/api_service.dart';
import '../services/audio_cache_service.dart';
import '../theme/app_design.dart';
import '../widgets/audio_analysis_progress_widget.dart';

Map<String, dynamic> _buildAudioPreprocessingInBackground(
  Map<String, dynamic> args,
) {
  final bytes = args['bytes'] as Uint8List;
  final ext = args['ext'] as String;
  final hash = sha256.convert(bytes).toString();

  int readLe16(Uint8List b, int off) {
    if (off + 1 >= b.length) return 0;
    return b[off] | (b[off + 1] << 8);
  }

  int readLe32(Uint8List b, int off) {
    if (off + 3 >= b.length) return 0;
    return b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24);
  }

  bool isWav(Uint8List b) {
    if (b.length < 12) return false;
    final riff = ascii.decode(b.sublist(0, 4), allowInvalid: true);
    final wave = ascii.decode(b.sublist(8, 12), allowInvalid: true);
    return riff == 'RIFF' && wave == 'WAVE';
  }

  Map<String, dynamic>? extractWavFeatures(Uint8List value) {
    if (!isWav(value) || value.length < 44) return null;

    int offset = 12;
    int sampleRate = 0;
    int channels = 0;
    int bitsPerSample = 0;
    int dataOffset = -1;
    int dataSize = 0;

    while (offset + 8 <= value.length) {
      final id =
          ascii.decode(value.sublist(offset, offset + 4), allowInvalid: true);
      final size = readLe32(value, offset + 4);
      final chunkStart = offset + 8;
      final next = chunkStart + size + (size % 2);

      if (id == 'fmt ' && size >= 16 && chunkStart + 16 <= value.length) {
        channels = readLe16(value, chunkStart + 2);
        sampleRate = readLe32(value, chunkStart + 4);
        bitsPerSample = readLe16(value, chunkStart + 14);
      } else if (id == 'data') {
        dataOffset = chunkStart;
        dataSize = size;
        break;
      }

      if (next <= offset) break;
      offset = next;
    }

    if (dataOffset < 0 ||
        sampleRate <= 0 ||
        channels <= 0 ||
        bitsPerSample != 16) {
      return {
        'wav_detected': true,
        'sample_rate_hz': sampleRate,
        'channels': channels,
        'bits_per_sample': bitsPerSample,
      };
    }

    final available = math.max(0, value.length - dataOffset);
    final useSize = math.min(dataSize, available);
    final frameSize = channels * 2;
    final totalFrames = frameSize > 0 ? useSize ~/ frameSize : 0;
    if (totalFrames <= 0) {
      return {
        'wav_detected': true,
        'sample_rate_hz': sampleRate,
        'channels': channels,
        'bits_per_sample': bitsPerSample,
      };
    }

    double sumSq = 0.0;
    double peak = 0.0;
    int zeroCrossings = 0;
    double prev = 0.0;
    bool hasPrev = false;

    for (int i = 0; i < totalFrames; i++) {
      final sampleOffset = dataOffset + (i * frameSize);
      final s = readLe16(value, sampleOffset);
      final signed = s > 32767 ? s - 65536 : s;
      final norm = signed / 32768.0;

      sumSq += norm * norm;
      peak = math.max(peak, norm.abs());
      if (hasPrev && ((prev >= 0 && norm < 0) || (prev < 0 && norm >= 0))) {
        zeroCrossings += 1;
      }
      prev = norm;
      hasPrev = true;
    }

    final rms = math.sqrt(sumSq / totalFrames);
    final durationSec = totalFrames / sampleRate;
    final zcr = durationSec > 0 ? zeroCrossings / durationSec : 0.0;

    return {
      'wav_detected': true,
      'sample_rate_hz': sampleRate,
      'channels': channels,
      'bits_per_sample': bitsPerSample,
      'duration_sec': durationSec,
      'rms_energy': rms,
      'peak_amplitude': peak,
      'zero_crossing_rate_hz': zcr,
    };
  }

  return {
    'pipeline_version': 'device-pre-v1',
    'modality': 'audio',
    'file_ext': ext,
    'file_size_bytes': bytes.length,
    'sha256': hash,
    'captured_at': DateTime.now().toUtc().toIso8601String(),
    if (ext == 'wav') 'wav_features': extractWavFeatures(bytes),
  };
}

class AudioAssessmentScreen extends StatefulWidget {
  static const routeName = '/audio-assessment';
  const AudioAssessmentScreen({super.key});

  @override
  State<AudioAssessmentScreen> createState() => _AudioAssessmentScreenState();
}

enum AudioPhase { idle, uploading, analyzing, done, error }

class _AudioAssessmentScreenState extends State<AudioAssessmentScreen> {
  static const Duration _analysisCooldown = Duration(seconds: 3);
  static const Duration _analysisTimeout = Duration(seconds: 35);
  static const int _maxRetries = 2;

  // For recording timer
  Timer? _recordTimer;
  int _recordSeconds = 0;
  final _api = ApiService();
  final AudioService _audioService = AudioService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isPlayingAudio = false;
  bool _loading = false;
  String? _error;
  bool _isRecording = false;
  Uint8List? _audioBytes;
  String? _audioFileName;
  String? _audioExt;
  String? _sourceLabel;
  Map<String, dynamic>? _audioAnalysis;
  Map<String, dynamic>? _eegFeatures;
  String? _assessmentType;
  String? _preReportId;
  Map<String, dynamic>? _child;
  bool _isPickingAudio = false;
  bool _analysisInFlight = false;
  double? _uploadProgress;
  String? _uploadStatus;
  CancelToken? _audioUploadCancelToken;
  AudioPhase _phase = AudioPhase.idle;
  AudioAnalysisStage _stage = AudioAnalysisStage.idle;
  String? _selectedAudioFingerprint;
  String? _lastAnalyzedFingerprint;
  DateTime? _lastAnalysisAttemptAt;
  bool _wasLoadedFromCache = false;

  bool get _hasValidAudioAnalysis {
    final analysis = _audioAnalysis;
    if (analysis == null) return false;
    if (analysis['valid'] == false || analysis['silence_detected'] == true) {
      return false;
    }
    return _numFrom(analysis, ['fluency_score']) != null;
  }

  String? get _lowConfidenceWarning {
    final analysis = _audioAnalysis;
    if (analysis == null) return null;
    if (analysis['low_confidence'] == true) {
      final warning = analysis['warning']?.toString().trim();
      if (warning != null && warning.isNotEmpty) {
        return warning;
      }
      return null;
    }
    return null;
  }

  String _friendlyError(Object error) {
    String extractError(Object? payload) {
      if (payload == null) return '';
      if (payload is Map) {
        return payload['error']?.toString() ?? payload['message']?.toString() ?? payload.toString();
      }
      if (payload is String) {
        final trimmed = payload.trim();
        if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
          try {
            final decoded = jsonDecode(trimmed);
            return extractError(decoded);
          } catch (_) {
            return trimmed;
          }
        }
        return trimmed;
      }
      return payload.toString();
    }

    String text;
    if (error is DioException) {
      text = extractError(error.response?.data);
      if (text.isEmpty) {
        final statusCode = error.response?.statusCode;
        final statusMessage = error.response?.statusMessage;
        text = error.message ?? '';
        if (statusCode != null) {
          text = 'Server responded with $statusCode${statusMessage != null ? ': $statusMessage' : ''}';
        }
      }
    } else {
      text = extractError(error);
    }

    text = text.replaceFirst('Exception: ', '').trim();
    const prefix = 'audio analysis failed:';
    if (text.toLowerCase().startsWith(prefix)) {
      text = text.substring(prefix.length).trim();
    }
    return text.isEmpty ? 'Something went wrong. Please try again.' : text;
  }

  String _buildRequestId(String childId) {
    final ts = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'audio-$childId-$ts';
  }

  String _fingerprintBytes(Uint8List bytes) => sha256.convert(bytes).toString();

  bool get _isInAnalysisCooldown {
    final lastAttempt = _lastAnalysisAttemptAt;
    if (lastAttempt == null) return false;
    return DateTime.now().difference(lastAttempt) < _analysisCooldown;
  }

  @override
  void initState() {
    super.initState();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlayingAudio = state == PlayerState.playing;
      });
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _audioPlayer.dispose();
    unawaited(_audioService.dispose());
    super.dispose();
  }

  Future<void> _playAudio() async {
    if (_audioBytes == null) return;

    try {
      await _audioPlayer.stop();

      if (kIsWeb) {
        await _audioPlayer.play(BytesSource(_audioBytes!));
      } else {
        final ext = _audioExt ?? 'wav';
        final tempFile = File('${Directory.systemTemp.path}/playback_audio.$ext');
        await tempFile.writeAsBytes(_audioBytes!, flush: true);
        await _audioPlayer.play(DeviceFileSource(tempFile.path));
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    } catch (e) {
      debugPrint('[AUDIO] Play failed: $e');
    }
  }

  Future<void> _startRecording() async {
    if (_loading || _isPickingAudio || _isRecording) return;
    try {
      await _audioService.startRecording();
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
        _error = null;
        _audioBytes = null;
        _sourceLabel = 'Recording in progress...';
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordSeconds++;
        });
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to start recording: $e';
      });
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    try {
      final bytes = await _audioService.stopRecording();
      setState(() {
        _isRecording = false;
        _audioBytes = bytes;
        _audioExt = 'wav';
        _audioFileName = 'recorded_audio.wav';
        _sourceLabel = bytes != null ? 'Recorded audio' : 'Recording failed. Please try again.';
        if (bytes != null) {
          _selectedAudioFingerprint = _fingerprintBytes(bytes);
        }
        _lastAnalyzedFingerprint = null;
        _audioAnalysis = null;
        _phase = AudioPhase.idle;
        _stage = AudioAnalysisStage.idle;
      });
      if (bytes != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording complete. You can play it back or analyze it.')),
        );
      }
    } catch (e) {
      setState(() {
        _isRecording = false;
        _error = 'Failed to stop recording: $e';
      });
    }
  }

  Future<void> _pickAudioFile() async {
    if (_loading || _isPickingAudio || _isRecording) return;
    _recordTimer?.cancel();
    setState(() {
      _isPickingAudio = true;
      _error = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: kIsWeb ? FileType.custom : FileType.audio,
        allowedExtensions: kIsWeb ? ['m4a', 'mp3', 'wav', 'webm'] : null,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final picked = result.files.single;
        final path = kIsWeb ? null : picked.path;
        final bytes = picked.bytes;
        final ext =
            (picked.extension ?? picked.name.split('.').last).toLowerCase();
        const allowed = ['wav', 'mp3', 'm4a', 'webm'];
        if (!allowed.contains(ext)) {
          setState(() {
            _error =
                'Unsupported audio format. Please select a WAV, MP3, M4A, or WEBM file.';
          });
          return;
        }
        if (path == null && bytes == null) {
          setState(() {
            _error = 'Could not read selected audio file.';
          });
          return;
        }
        final resolvedBytes = bytes!;
        final fingerprint = _fingerprintBytes(resolvedBytes);
        setState(() {
          _audioBytes = resolvedBytes;
          _audioFileName = picked.name;
          _audioExt = ext;
          _sourceLabel = 'Uploaded file: ${picked.name}';
          _isRecording = false;
          _audioAnalysis = null;
          _selectedAudioFingerprint = fingerprint;
          _lastAnalyzedFingerprint = null;
          _phase = AudioPhase.idle;
          _stage = AudioAnalysisStage.idle;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to pick audio file: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingAudio = false);
      }
    }
  }

  Future<void> _runAnalysis(String childId) async {
    if (_loading || _analysisInFlight) return;
    if (_audioBytes == null) {
      setState(() => _error = 'Please record or upload an audio sample first.');
      return;
    }
    if (_isInAnalysisCooldown) {
      debugPrint('[AUDIO] Blocked duplicate trigger during cooldown');
      setState(() {
        _error = 'Please wait a moment before analyzing again.';
      });
      return;
    }
    if (_audioAnalysis != null &&
        _selectedAudioFingerprint != null &&
        _selectedAudioFingerprint == _lastAnalyzedFingerprint) {
      debugPrint('[AUDIO] Blocked duplicate analysis for unchanged audio sample');
      setState(() {
        _error =
            'This audio sample has already been analyzed. Record or upload a new sample to run again.';
      });
      return;
    }

    // Check for cached result first
    final fingerprint = _selectedAudioFingerprint;
    if (fingerprint != null) {
      final cached =
          await AudioCacheService.getCachedAnalysis(fingerprint);
      if (cached != null && mounted) {
        debugPrint('[AUDIO] Loaded cached analysis for fingerprint=$fingerprint');
        setState(() {
          _audioAnalysis = cached;
          _wasLoadedFromCache = true;
          _error = null;
          _phase = AudioPhase.done;
          _stage = AudioAnalysisStage.cached;
          _lastAnalyzedFingerprint = fingerprint;
          _loading = false;
        });
        // Show brief cache indicator
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          setState(() {
            _stage = AudioAnalysisStage.idle;
          });
        }
        return;
      }
    }

    _analysisInFlight = true;
    _lastAnalysisAttemptAt = DateTime.now();
    _audioUploadCancelToken = CancelToken();
    final requestId = _buildRequestId(childId);

    debugPrint(
        '[AUDIO] Running analysis requestId=$requestId childId=$childId, bytes=${_audioBytes?.length}');

    setState(() {
      _loading = true;
      _error = null;
      _uploadProgress = null;
      _uploadStatus = null;
      _wasLoadedFromCache = false;
      _phase = AudioPhase.uploading;
      _stage = AudioAnalysisStage.uploading;
    });

    try {
      final bytes = _audioBytes!;
      debugPrint("🎙️ Audio bytes length before validation: ${bytes.length}");
      if (bytes.length < 5000) {
        setState(() => _error = 'Audio recording is too short. Please record or upload a clearer, longer sample.');
        return;
      }

      final ext = _audioExt ?? 'wav';
      final devicePreprocessing =
          await compute(_buildAudioPreprocessingInBackground, {
        'bytes': bytes,
        'ext': ext,
      });
      final uploadPayload = await AudioCompressor.compressForUpload(
        bytes,
        inputExt: ext,
      );

      debugPrint(
        '[AUDIO] Upload payload ext=${uploadPayload.ext}, '
        'originalBytes=${bytes.length}, uploadBytes=${uploadPayload.bytes.length}, '
        'compressed=${uploadPayload.wasCompressed}',
      );

      if (uploadPayload.bytes.isEmpty) {
        setState(() => _error = 'Audio compression failed. Please try recording again.');
        return;
      }

      if (!mounted) return;

      // Attempt analysis with timeout and retry logic
      final audioAnalysis = await _performAnalysisWithRetry(
        childId,
        uploadPayload,
        devicePreprocessing,
        requestId,
      );

      if (!mounted) return;
      setState(() {
        _uploadProgress = 1.0;
        _phase = AudioPhase.analyzing;
        _stage = AudioAnalysisStage.generating;
      });

      if (audioAnalysis['valid'] == false ||
          audioAnalysis['silence_detected'] == true) {
        _audioAnalysis = null;
        _error = (audioAnalysis['error'] ??
                'No speech detected. Please speak clearly and try again.')
            .toString();
        _phase = AudioPhase.error;
        _stage = AudioAnalysisStage.error;
      } else {
        _audioAnalysis = audioAnalysis;
        _error = null;
        _phase = AudioPhase.done;
        _stage = AudioAnalysisStage.done;
        _lastAnalyzedFingerprint = _selectedAudioFingerprint;

        // Cache the result
        if (_selectedAudioFingerprint != null) {
          try {
            await AudioCacheService.cacheAnalysis(
                _selectedAudioFingerprint!, audioAnalysis);
            debugPrint(
                '[AUDIO] Cached analysis result for fingerprint=$_selectedAudioFingerprint');
          } catch (e) {
            debugPrint('[AUDIO] Failed to cache result: $e');
          }
        }
      }
    } catch (e) {
      setState(() {
        _audioAnalysis = null;
        _error = _mapErrorMessage(e);
        _phase = _error == 'Audio upload cancelled.'
            ? AudioPhase.idle
            : AudioPhase.error;
        _stage = AudioAnalysisStage.error;
      });
    } finally {
      _audioUploadCancelToken = null;
      _analysisInFlight = false;
      if (mounted) {
        setState(() {
          _loading = false;
          _uploadProgress = null;
          _uploadStatus = null;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _performAnalysisWithRetry(
    String childId,
    dynamic uploadPayload,
    Map<String, dynamic> devicePreprocessing,
    String requestId,
  ) async {
    int attempt = 0;

    while (attempt <= _maxRetries) {
      attempt++;
      debugPrint('[AUDIO] Attempt $attempt/${_maxRetries + 1}');

      try {
        if (!mounted) return {};
        setState(() {
          _phase = AudioPhase.uploading;
          _stage = AudioAnalysisStage.uploading;
        });

        final audioAnalysis = await _api
            .analyzeAudio(
          childId,
          uploadPayload.bytes,
          ext: uploadPayload.ext,
          devicePreprocessing: devicePreprocessing,
          requestId: requestId,
          cancelToken: _audioUploadCancelToken,
          onSendProgress: (sent, total) {
            if (!mounted) return;
            final progress = total > 0 ? sent / total : null;
            final isUploadDone = progress != null && progress >= 0.999;
            setState(() {
              _uploadProgress = progress?.clamp(0.0, 1.0);
              _phase = isUploadDone ? AudioPhase.analyzing : AudioPhase.uploading;
              _stage = isUploadDone
                  ? AudioAnalysisStage.analyzing
                  : AudioAnalysisStage.uploading;
            });
          },
        )
            .timeout(
          _analysisTimeout,
          onTimeout: () => throw TimeoutException(
              'Analysis took too long (${_analysisTimeout.inSeconds}s)'),
        );

        return audioAnalysis;
      } on TimeoutException catch (e) {
        debugPrint('[AUDIO] Timeout on attempt $attempt: $e');
        if (attempt > _maxRetries) {
          rethrow;
        }

        // Show retry dialog
        if (mounted) {
          final shouldRetry = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Server Busy'),
              content: const Text(
                  'The analysis took too long. Would you like to try again?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );

          if (shouldRetry != true) {
            throw e;
          }
        } else {
          rethrow;
        }
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          rethrow;
        }
        debugPrint('[AUDIO] DioException on attempt $attempt: $e');
        if (attempt > _maxRetries) {
          rethrow;
        }

        // Show retry dialog for other errors
        if (mounted) {
          final shouldRetry = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Network Issue'),
              content: Text(
                  'Failed to analyze (attempt $attempt/${ _maxRetries + 1}). Retry?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );

          if (shouldRetry != true) {
            rethrow;
          }
        } else {
          rethrow;
        }
      }
    }

    return {};
  }

  String _mapErrorMessage(Object error) {
    if (error is TimeoutException) {
      return 'Analysis took too long. Check your internet and try again.';
    }

    if (error is DioException) {
      if (error.type == DioExceptionType.cancel) {
        return 'Audio upload cancelled.';
      }
      final statusCode = error.response?.statusCode;
      if (statusCode == 502 || statusCode == 503) {
        return 'Server is busy. Please try again in a moment.';
      }
      if (statusCode == 408) {
        return 'Request timed out. Please try again.';
      }
      if (statusCode == null) {
        // Network error
        return 'Network error. Check your connection and try again.';
      }
      return 'Server error ($statusCode). Please try again.';
    }

    return _friendlyError(error);
  }

  void _cancelAudioUpload() {
    _audioUploadCancelToken?.cancel('User cancelled audio upload.');
    setState(() {
      _uploadProgress = 0.0;
      _uploadStatus = null;
      _phase = AudioPhase.idle;
      _stage = AudioAnalysisStage.idle;
    });
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
    final text = key.replaceAll('_', ' ').trim();
    if (text.isEmpty) return key;
    return text[0].toUpperCase() + text.substring(1);
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

  String _labelFromClass(int cls) {
    if (cls <= 0) return 'low';
    if (cls == 1) return 'medium';
    return 'high';
  }

  String _formatFieldValue(String key, dynamic value) {
    if (value == null) return 'N/A';
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is num) {
      final numValue = value.toDouble();
      if (key.contains('sample_rate') ||
          key.contains('hz') ||
          key.contains('frequency')) {
        return '${_formatNumber(numValue)} Hz';
      }
      if (key.contains('duration') || key.contains('time_sec')) {
        return '${_formatNumber(numValue)} sec';
      }
      if (key.contains('size') || key.contains('bytes')) {
        return '${(numValue / 1024).toStringAsFixed(1)} KB';
      }
      if (key.contains('bits') || key.contains('bit_depth')) {
        return '${numValue.toInt()} bit';
      }
      if (key.contains('energy') ||
          key.contains('rms') ||
          key.contains('amplitude')) {
        return _formatNumber(numValue);
      }
      if (key.contains('confidence') || key.contains('probability')) {
        return '${(numValue * 100).toStringAsFixed(1)}%';
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

    // Build filtered entries
    final filteredEntries = <MapEntry<String, dynamic>>[];
    for (final entry in data.entries) {
      final key = entry.key.toLowerCase();
      // Check if this key matches any important field (partial match)
      final isImportant =
          importantKeys.any((imp) => key.contains(imp.toLowerCase()));

      if (isImportant && !key.startsWith('_') && entry.value != null) {
        filteredEntries.add(entry);
      }
    }

    // Group by category
    final grouped = <String, List<MapEntry<String, dynamic>>>{
      'Fluency Metrics': [],
      'Signal Properties': [],
      'Other': [],
    };

    for (final entry in filteredEntries) {
      final key = entry.key.toLowerCase();
      if (key.contains('fluency') ||
          key.contains('confidence') ||
          key.contains('label') ||
          key.contains('class') ||
          key.contains('prediction')) {
        grouped['Fluency Metrics']!.add(entry);
      } else if (key.contains('duration') ||
          key.contains('energy') ||
          key.contains('sample_rate') ||
          key.contains('hz')) {
        grouped['Signal Properties']!.add(entry);
      } else {
        grouped['Other']!.add(entry);
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

  Widget _buildAudioResult(Map<String, dynamic> data) {
    final clsNum = _numFrom(data, ['fluency_class', 'class', 'prediction']);
    final cls = clsNum?.round();
    final fluencyLabel = (_strFrom(data, ['fluency_label', 'label']) ??
            (cls != null ? _labelFromClass(cls) : 'unknown'))
        .toLowerCase();
    final score = _numFrom(data, ['fluency_score']);
    final confidence = _numFrom(data, ['confidence']);
    final cards = <Widget>[
      _metricTile('Fluency', fluencyLabel),
      if (score != null)
        _metricTile('Score', '${score.toStringAsFixed(1)} / 100'),
      if (confidence != null)
        _metricTile('Confidence', '${(confidence * 100).toStringAsFixed(0)}%'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Result (Audio File)',
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
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text('Technical details',
                    style: TextStyle(fontSize: 13)),
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: _buildTechnicalDetailsWidget(data,
                            modality: 'audio'),
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

  void _continueToPreAssessment(String childId) {
    if (!_hasValidAudioAnalysis) {
      setState(() {
        _error = 'Please analyse a valid speech sample first.';
      });
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      '/pre-assessment',
      arguments: {
        if (_child != null) 'child': _child,
        'childId': childId,
        'audioAnalysis': _audioAnalysis,
        if (_eegFeatures != null) 'eegFeatures': _eegFeatures,
        if (_assessmentType != null) 'assessmentType': _assessmentType,
        if (_preReportId != null && _preReportId!.isNotEmpty)
          'preReportId': _preReportId,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Recording timer display
    Widget? recordingTimer;
    if (_isRecording) {
      recordingTimer = Row(
        children: [
          const Icon(Icons.timer, size: 18),
          const SizedBox(width: 6),
          Text('Recording: $_recordSeconds s',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      );
    }

    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    String childId = '1';
    if (routeArgs is Map) {
      final m = routeArgs;
      _child = m['child'] is Map
          ? (m['child'] as Map).cast<String, dynamic>()
          : null;
      childId = m['childId']?.toString() ?? '1';
      _assessmentType =
          m['assessmentType'] is String ? m['assessmentType'] as String : null;
      _preReportId = m['preReportId']?.toString();
      final ef = m['eegFeatures'];
      if (ef is Map) {
        _eegFeatures = ef.cast<String, dynamic>();
      }
    } else if (routeArgs is String) {
      childId = routeArgs;
      _child = null;
      _eegFeatures = null;
      _assessmentType = null;
      _preReportId = null;
    } else {
      _child = null;
      _eegFeatures = null;
      _assessmentType = null;
      _preReportId = null;
      childId = '1';
    }

    if (_eegFeatures == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audio Assessment')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'EEG data is missing. Please return to EEG upload and try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to EEG Upload'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Audio Assessment')),
      body: SingleChildScrollView(
        padding: AppDesign.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Record or upload a clear speech sample. The model evaluates fluency and confidence before you continue.',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (!_isRecording)
                  ElevatedButton.icon(
                    onPressed: _startRecording,
                    icon: const Icon(Icons.mic),
                    label: const Text('Record Audio'),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _stopRecording,
                    icon: const Icon(Icons.stop),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                    label: const Text('Stop Recording'),
                  ),
                OutlinedButton.icon(
                  onPressed: _isRecording ? null : _pickAudioFile,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload Audio'),
                ),
                if (_audioBytes != null && !_isRecording)
                  OutlinedButton.icon(
                    onPressed: _playAudio,
                    icon: Icon(_isPlayingAudio ? Icons.pause : Icons.play_arrow),
                    label: Text(_isPlayingAudio ? 'Playing...' : 'Play Sample'),
                  ),
              ],
            ),
            if (_audioBytes != null) ...[
              const SizedBox(height: 8),
              const Text(
                '🎧 Use Play Sample to verify recorded/uploaded audio playback before analysis.',
                style: TextStyle(fontSize: 13, color: Colors.blueGrey),
              ),
            ],
            if (recordingTimer != null) ...[
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: recordingTimer,
              ),
            ],
            const SizedBox(height: 14),
            Text(
              _sourceLabel ?? 'No audio selected yet.',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            if (_sourceLabel != null && !_isRecording) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  border: Border.all(
                      color: AppDesign.primary.withValues(alpha: 0.45)),
                  borderRadius: BorderRadius.circular(AppDesign.radiusM),
                ),
                child: Text(
                  'Upload status: File uploaded\n'
                  'File type: Audio\n'
                  'File name: ${_audioFileName ?? 'N/A'}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 20),
            if (_loading) ...[
              AudioAnalysisProgressWidget(
                stage: _stage,
                uploadProgress: _uploadProgress,
                customMessage: _wasLoadedFromCache
                    ? 'Loading from cache...'
                    : null,
                onCancel: _audioUploadCancelToken == null
                    ? null
                    : _cancelAudioUpload,
              ),
            ],
            if (!_loading)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      (_audioBytes == null || _isInAnalysisCooldown)
                          ? null
                          : () => _runAnalysis(childId),
                  child: const Text('Analyze Audio'),
                ),
              ),
            if (_audioAnalysis != null) ...[
              const SizedBox(height: 14),
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: _buildAudioResult(_audioAnalysis!),
              ),
              if (_lowConfidenceWarning != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withValues(alpha: 0.15),
                    border: Border.all(
                        color: Colors.orangeAccent.withValues(alpha: 0.6)),
                    borderRadius: BorderRadius.circular(AppDesign.radiusM),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.warning_amber_rounded,
                            color: Colors.orangeAccent),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_lowConfidenceWarning!)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading || !_hasValidAudioAnalysis
                      ? null
                      : () => _continueToPreAssessment(childId),
                  child: const Text('Continue to Behavioral Assessment'),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
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
          ],
        ),
      ),
    );
  }
}
