import 'dart:typed_data';

/// Stub implementation that throws on unsupported platforms.
Future<String?> exportPngImpl(Uint8List bytes, {String filename = 'battlebox.png'}) {
  throw UnsupportedError('Image export not supported on this platform');
}
