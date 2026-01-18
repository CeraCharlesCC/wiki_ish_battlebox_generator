import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

/// Web implementation using browser download.
Future<String?> exportPngImpl(Uint8List bytes, {String filename = 'battlebox.png'}) async {
  final base64 = base64Encode(bytes);
  final dataUrl = 'data:image/png;base64,$base64';
  html.AnchorElement(href: dataUrl)
    ..setAttribute('download', filename)
    ..click();
  return filename;
}
