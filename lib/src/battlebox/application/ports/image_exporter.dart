import 'dart:typed_data';

/// Port for exporting images to the file system or downloads.
///
/// Different platforms (web, mobile, desktop) have different
/// mechanisms for saving/downloading files.
abstract class ImageExporter {
  /// Exports PNG bytes, returning the path/URL or null on failure.
  ///
  /// [bytes] The PNG image data.
  /// [filename] The suggested filename for the export.
  Future<String?> exportPng(Uint8List bytes, {String filename = 'battlebox.png'});
}
