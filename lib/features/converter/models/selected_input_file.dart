import 'dart:io';

import '../../../services/conversion_models.dart';

class SelectedInputFile {
  const SelectedInputFile({
    required this.path,
    required this.name,
    required this.extension,
    required this.sizeBytes,
    required this.sourceFormat,
  });

  final String path;
  final String name;
  final String extension;
  final int sizeBytes;
  final ConversionFormat sourceFormat;

  String get directoryPath => File(path).parent.path;

  String get baseName {
    final extensionLength = extension.length + 1;
    return name.length > extensionLength
        ? name.substring(0, name.length - extensionLength)
        : name;
  }

  static Future<SelectedInputFile?> fromPath(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }

    final name = _fileName(path);
    final dotIndex = name.lastIndexOf('.');
    final extension = dotIndex > 0
        ? name.substring(dotIndex + 1).toLowerCase()
        : '';
    final sourceFormat = ConversionFormat.values
        .where((format) => format.extension == extension)
        .firstOrNull;
    if (sourceFormat == null) {
      return null;
    }

    return SelectedInputFile(
      path: file.absolute.path,
      name: name,
      extension: extension,
      sizeBytes: await file.length(),
      sourceFormat: sourceFormat,
    );
  }

  static String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }
}
