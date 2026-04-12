// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class AudioService {
  html.MediaRecorder? _webRecorder;
  html.MediaStream? _webStream;
  final List<html.Blob> _webChunks = [];
  String _recordedMimeType = 'audio/webm';

  Future<bool> isRecording() async {
    return _webRecorder != null && _webRecorder!.state == 'recording';
  }

  Future<void> startRecording() async {
    final devices = html.window.navigator.mediaDevices;
    if (devices == null) {
      throw StateError('Audio recording is not supported in this browser.');
    }

    final stream = await devices.getUserMedia({'audio': true});
    _webStream = stream;
    _webChunks.clear();

    const preferredTypes = ['audio/webm;codecs=opus', 'audio/webm'];
    String? mimeType;
    for (final candidate in preferredTypes) {
      if (html.MediaRecorder.isTypeSupported(candidate)) {
        mimeType = candidate;
        break;
      }
    }

    _recordedMimeType = mimeType ?? 'audio/webm';
    _webRecorder = mimeType != null
        ? html.MediaRecorder(stream, {'mimeType': mimeType})
        : html.MediaRecorder(stream);

    _webRecorder!.addEventListener('dataavailable', (event) {
      final dataEvent = event as dynamic;
      final blob = dataEvent.data is html.Blob ? dataEvent.data as html.Blob : null;
      if (blob != null && blob.size > 0) {
        _webChunks.add(blob);
      }
    });

    _webRecorder!.start();
  }

  Future<Uint8List?> stopRecording() async {
    final recorder = _webRecorder;
    if (recorder == null) return null;

    final completer = Completer<Uint8List?>();

    void onStopHandler(html.Event event) async {
      try {
        if (_webChunks.isEmpty) {
          completer.complete(null);
          return;
        }

        final blob = html.Blob(_webChunks, _recordedMimeType);
        final reader = html.FileReader();
        reader.readAsArrayBuffer(blob);
        await reader.onLoad.first;

        final result = reader.result;
        if (result is ByteBuffer) {
          completer.complete(Uint8List.view(result));
        } else if (result is Uint8List) {
          completer.complete(result);
        } else {
          completer.complete(null);
        }
      } catch (e) {
        completer.completeError(e);
      } finally {
        recorder.removeEventListener('stop', onStopHandler);
        for (final track in _webStream?.getTracks() ?? const <html.MediaStreamTrack>[]) {
          track.stop();
        }
        _webStream = null;
        _webRecorder = null;
        _webChunks.clear();
      }
    }

    recorder.addEventListener('stop', onStopHandler);
    recorder.stop();
    return completer.future;
  }
}
