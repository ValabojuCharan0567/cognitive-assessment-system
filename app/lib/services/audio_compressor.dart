import 'dart:typed_data';

import 'audio_compressor_mobile.dart'
    if (dart.library.html) 'audio_compressor_web.dart' as impl;

class CompressedAudioPayload {
  const CompressedAudioPayload({
    required this.bytes,
    required this.ext,
    this.wasCompressed = false,
  });

  final Uint8List bytes;
  final String ext;
  final bool wasCompressed;
}

class AudioCompressor {
  static Future<CompressedAudioPayload> compressForUpload(
    Uint8List bytes, {
    required String inputExt,
  }) {
    return impl.compressForUpload(bytes, inputExt: inputExt);
  }
}

