import 'dart:typed_data';

import '../../application/ports/image_exporter.dart';
import 'image_exporter_stub.dart'
    if (dart.library.html) 'image_exporter_web.dart'
    if (dart.library.io) 'image_exporter_io.dart' as platform;

/// Platform-aware implementation of ImageExporter.
///
/// Uses conditional imports to delegate to the appropriate platform implementation.
class PlatformImageExporter implements ImageExporter {
  const PlatformImageExporter();

  @override
  Future<String?> exportPng(Uint8List bytes, {String filename = 'battlebox.png'}) {
    return platform.exportPngImpl(bytes, filename: filename);
  }
}
