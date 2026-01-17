import 'dart:typed_data';

Future<String?> exportPngImpl(
  Uint8List bytes, {
  String filename = 'battlebox.png',
}) async {
  throw UnsupportedError('Image export is not supported on this platform.');
}
