import 'dart:typed_data';

import 'image_exporter_stub.dart'
    if (dart.library.html) 'image_exporter_web.dart'
    if (dart.library.io) 'image_exporter_io.dart';

Future<String?> exportPng(
  Uint8List bytes, {
  String filename = 'battlebox.png',
}) {
  return exportPngImpl(bytes, filename: filename);
}
