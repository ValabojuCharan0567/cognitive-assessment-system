import 'dart:io' show Directory, File;
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioService {
  final _audioRecorder = AudioRecorder();
  String? _recordingPath;

  Future<bool> isRecording() async {
    return await _audioRecorder.isRecording();
  }

  Future<void> startRecording() async {
    // Request microphone permission
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw Exception('Microphone permission denied');
    }

    final tempDir = await Directory.systemTemp.createTemp('neuro_ai_audio_');
    _recordingPath = '${tempDir.path}/recorded_audio.wav';
    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: _recordingPath!,
    );
    debugPrint('[AUDIO DEBUG] Recording started at $_recordingPath with 44.1kHz/128kbps/mono');
  }

  Future<Uint8List?> stopRecording() async {
    final path = await _audioRecorder.stop();
    final resolvedPath = path ?? _recordingPath;
    if (resolvedPath == null) return null;
    final file = File(resolvedPath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    debugPrint('[AUDIO DEBUG] Recording stopped, bytes=${bytes.length}, path=$resolvedPath');
    await _cleanupRecordingArtifacts(resolvedPath);
    return bytes;
  }

  Future<void> dispose() async {
    try {
      await _audioRecorder.dispose();
    } catch (_) {}
    final path = _recordingPath;
    if (path != null) {
      await _cleanupRecordingArtifacts(path);
    }
  }

  Future<void> _cleanupRecordingArtifacts(String path) async {
    try {
      final file = File(path);
      final parent = file.parent;
      if (await file.exists()) {
        await file.delete();
      }
      if (await parent.exists()) {
        await parent.delete(recursive: true);
      }
    } catch (_) {}
    if (_recordingPath == path) {
      _recordingPath = null;
    }
  }
}
