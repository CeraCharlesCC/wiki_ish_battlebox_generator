// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'dart:typed_data';

Future<String?> exportPngImpl(
  Uint8List bytes, {
  String filename = 'battlebox.png',
}) async {
  final encoded = base64Encode(bytes);
  final anchor = html.AnchorElement(href: 'data:image/png;base64,$encoded')
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  return null;
}
