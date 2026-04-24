import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:ffmpeg_kit_audio_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_audio_flutter/return_code.dart';

import 'audio_compressor.dart';

Future<CompressedAudioPayload> compressForUpload(
  Uint8List bytes, {
  required String inputExt,
}) async {
  final normalizedExt = inputExt.trim().toLowerCase();

  // Skip compression for smaller audio payloads to reduce latency.
  if (bytes.lengthInBytes < 1 * 1024 * 1024) {
    return CompressedAudioPayload(
      bytes: bytes,
      ext: normalizedExt,
      wasCompressed: false,
    );
  }

  final tempDir = await Directory.systemTemp.createTemp('neuro_ai_audio_compress_');
  final inputPath = '${tempDir.path}/input.$normalizedExt';
  final outputPath = '${tempDir.path}/output.m4a';
  final inputFile = File(inputPath);
  final outputFile = File(outputPath);

  try {
    await inputFile.writeAsBytes(bytes, flush: true);

    final session = await FFmpegKit.execute(
      '-y -i ${_quote(inputPath)} '
      '-ac 1 -ar 16000 -b:a 32k -c:a aac -preset ultrafast '
      '${_quote(outputPath)}',
    );
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode) && await outputFile.exists()) {
      final compressedBytes = await outputFile.readAsBytes();
      if (compressedBytes.isNotEmpty && compressedBytes.length < bytes.length) {
        return CompressedAudioPayload(
          bytes: compressedBytes,
          ext: 'm4a',
          wasCompressed: true,
        );
      }
    }
  } catch (e) {
    debugPrint('[AUDIO DEBUG] Compression exception: $e');
    // Fall back to the original bytes when compression is unavailable or fails.
  } finally {
    try {
      if (await inputFile.exists()) {
        await inputFile.delete();
      }
    } catch (_) {}
    try {
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
    } catch (_) {}
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  return CompressedAudioPayload(
    bytes: bytes,
    ext: normalizedExt,
    wasCompressed: false,
  );
}

String _quote(String value) {
  final escaped = value.replaceAll("'", r"'\''");
  return "'$escaped'";
}

