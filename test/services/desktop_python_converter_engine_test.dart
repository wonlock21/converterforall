import 'dart:io';

import 'package:convertforall_flutter/services/conversion_models.dart';
import 'package:convertforall_flutter/services/converter_engine.dart';
import 'package:convertforall_flutter/services/desktop_python_converter_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  final venvPython = Platform.isWindows
      ? '$projectRoot${Platform.pathSeparator}.venv${Platform.pathSeparator}'
            'Scripts${Platform.pathSeparator}python.exe'
      : '$projectRoot${Platform.pathSeparator}.venv${Platform.pathSeparator}'
            'bin${Platform.pathSeparator}python';
  final pythonExecutable = File(venvPython).existsSync()
      ? venvPython
      : (Platform.isWindows ? 'python' : 'python3');
  final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  final workerSource = File(
    '$projectRoot${Platform.pathSeparator}backend'
    '${Platform.pathSeparator}worker.py',
  );

  test(
    'exchanges multiple structured requests with the Python worker',
    () async {
      final engine = DesktopPythonConverterEngine(
        pythonExecutable: pythonExecutable,
        projectRoot: projectRoot,
        isRelease: false,
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
    skip: isDesktop && workerSource.existsSync()
        ? false
        : 'Desktop Python test environment is not available.',
  );

  test('release mode never falls back to source Python', () async {
    var processWasStarted = false;
    final engine = DesktopPythonConverterEngine(
      pythonExecutable: 'python-must-not-run',
      projectRoot: projectRoot,
      isRelease: true,
      processStarter:
          (executable, arguments, {workingDirectory, environment}) async {
            processWasStarted = true;
            throw StateError('A process must not be started without a worker.');
          },
    );

    try {
      await expectLater(
        engine.convert(
          ConversionRequest(
            inputPath: '$projectRoot${Platform.pathSeparator}missing.pdf',
            outputPath: '$projectRoot${Platform.pathSeparator}missing.docx',
            sourceFormat: ConversionFormat.pdf,
            targetFormat: ConversionFormat.docx,
          ),
        ),
        throwsA(isA<ConverterEngineException>()),
      );
      expect(processWasStarted, isFalse);
    } finally {
      await engine.close();
    }
  });
}
