import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web implementation using browser download.
Future<String?> exportPngImpl(Uint8List bytes, {String filename = 'battlebox.png'}) async {
  final base64 = base64Encode(bytes);
  final dataUrl = 'data:image/png;base64,$base64';

  final anchor = web.HTMLAnchorElement()
    ..href = dataUrl
    ..download = filename
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  return filename;
}
