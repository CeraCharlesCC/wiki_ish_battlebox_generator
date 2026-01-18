import 'dart:io';
import 'dart:typed_data';

/// IO implementation for desktop/mobile platforms.
Future<String?> exportPngImpl(Uint8List bytes, {String filename = 'battlebox.png'}) async {
  final tempDir = Directory.systemTemp;
  final file = File('${tempDir.path}/$filename');
  await file.writeAsBytes(bytes);
  return file.path;
}
