import 'dart:io';

import 'package:convertforall_flutter/services/conversion_models.dart';
import 'package:convertforall_flutter/services/converter_engine.dart';
import 'package:convertforall_flutter/services/desktop_python_converter_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void _expectSingleOutputPathMatches(
  List<String> actualPaths,
  File expectedFile,
) {
  expect(actualPaths, hasLength(1));

  final actualFile = File(actualPaths.single);
  final actualName = actualFile.uri.pathSegments.last;
  final expectedName = expectedFile.uri.pathSegments.last;
  expect(
    Platform.isWindows ? actualName.toLowerCase() : actualName,
    Platform.isWindows ? expectedName.toLowerCase() : expectedName,
    reason: 'The worker returned an unexpected output file name.',
  );

  final actualParent = actualFile.parent;
  final expectedParent = expectedFile.absolute.parent;
  expect(
    actualParent.existsSync(),
    isTrue,
    reason: 'The worker returned a path in a directory that does not exist.',
  );
  expect(
    expectedParent.existsSync(),
    isTrue,
    reason: 'The expected output directory does not exist.',
  );

  // The planned output file does not exist yet, so resolve only its existing
  // parent directory. This also normalizes aliases such as /var vs
  // /private/var and Windows 8.3 short paths before comparison.
  final actualResolvedParent = actualParent.resolveSymbolicLinksSync();
  final expectedResolvedParent = expectedParent.resolveSymbolicLinksSync();
  expect(
    Platform.isWindows
        ? actualResolvedParent.toLowerCase()
        : actualResolvedParent,
    Platform.isWindows
        ? expectedResolvedParent.toLowerCase()
        : expectedResolvedParent,
    reason: 'The worker returned an output path in an unexpected directory.',
  );
}

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
        final capabilities = await engine.getSupportedConversions();
        expect(
          capabilities.any(
            (conversion) =>
                conversion.source == ConversionFormat.pdf &&
                conversion.target == ConversionFormat.png,
          ),
          isTrue,
        );
        expect(
          capabilities.any(
            (conversion) =>
                conversion.source == ConversionFormat.jpg &&
                conversion.target == ConversionFormat.png,
          ),
          isTrue,
        );
        expect(
          capabilities.any(
            (conversion) =>
                conversion.source == ConversionFormat.png &&
                conversion.target == ConversionFormat.jpeg,
          ),
          isTrue,
        );
        expect(
          capabilities.any(
            (conversion) =>
                conversion.source == ConversionFormat.png &&
                conversion.target == ConversionFormat.pdf,
          ),
          isTrue,
        );
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

  test(
    'converts a real PDF through the desktop JSON Lines adapter',
    () async {
      final tempDirectory = Directory.systemTemp.createTempSync(
        'convertforall-engine-',
      );
      final source = File(
        '${tempDirectory.path}${Platform.pathSeparator}source.pdf',
      );
      final output = File(
        '${tempDirectory.path}${Platform.pathSeparator}result.docx',
      );
      final textOutput = File(
        '${tempDirectory.path}${Platform.pathSeparator}result.txt',
      );
      final createPdf = Process.runSync(pythonExecutable, [
        '-c',
        'import pymupdf,sys; d=pymupdf.open(); p=d.new_page(); '
            'p.insert_text((72,72), "convertforall adapter test"); '
            'd.save(sys.argv[1]); d.close()',
        source.path,
      ]);
      expect(createPdf.exitCode, 0, reason: createPdf.stderr.toString());

      final engine = DesktopPythonConverterEngine(
        pythonExecutable: pythonExecutable,
        projectRoot: projectRoot,
        isRelease: false,
      );
      try {
        final textPlan = await engine.planConversion(
          ConversionRequest(
            inputPath: source.path,
            outputPath: textOutput.path,
            sourceFormat: ConversionFormat.pdf,
            targetFormat: ConversionFormat.txt,
          ),
        );
        expect(textPlan.success, isTrue, reason: textPlan.message);
        _expectSingleOutputPathMatches(textPlan.outputPaths, textOutput);
        expect(textPlan.conflictingOutputPaths, isEmpty);

        final result = await engine
            .convert(
              ConversionRequest(
                inputPath: source.path,
                outputPath: output.path,
                sourceFormat: ConversionFormat.pdf,
                targetFormat: ConversionFormat.docx,
              ),
            )
            .timeout(const Duration(seconds: 30));

        expect(result.success, isTrue, reason: result.message);
        expect(output.existsSync(), isTrue);
        expect(output.lengthSync(), greaterThan(0));

        final textResult = await engine.convert(
          ConversionRequest(
            inputPath: source.path,
            outputPath: textOutput.path,
            sourceFormat: ConversionFormat.pdf,
            targetFormat: ConversionFormat.txt,
          ),
        );
        expect(textResult.success, isTrue, reason: textResult.message);
        _expectSingleOutputPathMatches(textResult.outputPaths, textOutput);
        expect(textOutput.readAsStringSync(), contains('convertforall'));
      } finally {
        await engine.close();
        tempDirectory.deleteSync(recursive: true);
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
