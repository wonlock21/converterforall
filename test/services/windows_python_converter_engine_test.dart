import 'dart:io';

import 'package:convertforall_flutter/services/conversion_models.dart';
import 'package:convertforall_flutter/services/windows_python_converter_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  final pythonExecutable =
      '$projectRoot${Platform.pathSeparator}.venv${Platform.pathSeparator}'
      'Scripts${Platform.pathSeparator}python.exe';
  final canRunIntegration =
      Platform.isWindows &&
      File(pythonExecutable).existsSync() &&
      File(
        '$projectRoot${Platform.pathSeparator}backend'
        '${Platform.pathSeparator}worker.py',
      ).existsSync();

  test(
    'exchanges multiple structured requests with the Python worker',
    () async {
      final engine = WindowsPythonConverterEngine(
        pythonExecutable: pythonExecutable,
        projectRoot: projectRoot,
      );
      try {
        final results = await Future.wait([
          engine.convert(
            ConversionRequest(
              inputPath: '$projectRoot${Platform.pathSeparator}missing-one.pdf',
              outputPath: '$projectRoot${Platform.pathSeparator}one.docx',
              sourceFormat: ConversionFormat.pdf,
              targetFormat: ConversionFormat.docx,
            ),
          ),
          engine.convert(
            ConversionRequest(
              inputPath: '$projectRoot${Platform.pathSeparator}missing-two.pdf',
              outputPath: '$projectRoot${Platform.pathSeparator}two.docx',
              sourceFormat: ConversionFormat.pdf,
              targetFormat: ConversionFormat.docx,
            ),
          ),
        ]);

        expect(results, hasLength(2));
        expect(results.every((result) => !result.success), isTrue);
        expect(
          results.every((result) => result.errorCode == 'input_not_found'),
          isTrue,
        );
      } finally {
        await engine.close();
      }
    },
    skip: canRunIntegration
        ? false
        : 'Windows Python test environment is not available.',
  );
}
