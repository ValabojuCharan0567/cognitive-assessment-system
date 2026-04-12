import 'dart:typed_data';

import 'audio_compressor.dart';

Future<CompressedAudioPayload> compressForUpload(
  Uint8List bytes, {
  required String inputExt,
}) async {
  return CompressedAudioPayload(bytes: bytes, ext: inputExt, wasCompressed: false);
}

