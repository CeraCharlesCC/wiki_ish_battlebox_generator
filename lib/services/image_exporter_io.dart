import 'dart:io';
import 'dart:typed_data';

Future<String?> exportPngImpl(
  Uint8List bytes, {
  String filename = 'battlebox.png',
}) async {
  final tempDir = await Directory.systemTemp.createTemp('battlebox_');
  final file = File('${tempDir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
