import 'dart:io';

import 'package:convertforall_flutter/features/converter/models/selected_input_file.dart';
import 'package:convertforall_flutter/services/conversion_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads PDF metadata from a filesystem path', () async {
    final directory = Directory.systemTemp.createTempSync('selected-input-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}example.pdf')
      ..writeAsBytesSync(List<int>.filled(2048, 1));

    final selected = await SelectedInputFile.fromPath(file.path);

    expect(selected, isNotNull);
    expect(selected!.name, 'example.pdf');
    expect(selected.extension, 'pdf');
    expect(selected.sizeBytes, 2048);
    expect(selected.sourceFormat, ConversionFormat.pdf);
    expect(selected.directoryPath, directory.path);
    expect(selected.baseName, 'example');
  });
}
