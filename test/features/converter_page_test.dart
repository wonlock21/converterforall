import 'dart:async';
import 'dart:io';

import 'package:convertforall_flutter/features/converter/converter_page.dart';
import 'package:convertforall_flutter/features/converter/models/selected_input_file.dart';
import 'package:convertforall_flutter/services/conversion_models.dart';
import 'package:convertforall_flutter/services/converter_engine.dart';
import 'package:convertforall_flutter/services/file_actions.dart';
import 'package:convertforall_flutter/theme/app_theme.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingConverterEngine implements ConverterEngine {
  final requests = <ConversionRequest>[];
  Completer<ConversionResult>? pendingConversion;
  bool closed = false;

  @override
  Future<void> close() async => closed = true;

  @override
  Future<ConversionResult> convert(ConversionRequest request) {
    requests.add(request);
    final pending = pendingConversion;
    if (pending != null) return pending.future;
    return Future.value(
      ConversionResult(
        success: true,
        message: 'ok',
        durationMs: 12,
        inputPath: request.inputPath,
        outputPath: request.outputPath,
      ),
    );
  }

  @override
  Future<List<SupportedConversion>> getSupportedConversions() async => const [
    SupportedConversion(
      source: ConversionFormat.pdf,
      target: ConversionFormat.docx,
    ),
    SupportedConversion(
      source: ConversionFormat.pdf,
      target: ConversionFormat.txt,
    ),
    SupportedConversion(
      source: ConversionFormat.pdf,
      target: ConversionFormat.png,
    ),
    SupportedConversion(
      source: ConversionFormat.pdf,
      target: ConversionFormat.jpg,
    ),
    SupportedConversion(
      source: ConversionFormat.pdf,
      target: ConversionFormat.jpeg,
    ),
    SupportedConversion(
      source: ConversionFormat.jpg,
      target: ConversionFormat.pdf,
    ),
    SupportedConversion(
      source: ConversionFormat.jpg,
      target: ConversionFormat.png,
    ),
    SupportedConversion(
      source: ConversionFormat.jpeg,
      target: ConversionFormat.pdf,
    ),
    SupportedConversion(
      source: ConversionFormat.jpeg,
      target: ConversionFormat.png,
    ),
    SupportedConversion(
      source: ConversionFormat.png,
      target: ConversionFormat.pdf,
    ),
    SupportedConversion(
      source: ConversionFormat.png,
      target: ConversionFormat.jpg,
    ),
    SupportedConversion(
      source: ConversionFormat.png,
      target: ConversionFormat.jpeg,
    ),
  ];
}

class RecordingFileActions implements FileActions {
  String? openedPath;
  String? revealedPath;

  @override
  bool get isSupported => true;

  @override
  Future<void> openFile(String path) async => openedPath = path;

  @override
  Future<void> revealFile(String path) async => revealedPath = path;
}

void main() {
  late Directory tempDirectory;
  late File sourceFile;
  late RecordingConverterEngine engine;
  late RecordingFileActions fileActions;

  setUp(() {
    tempDirectory = Directory.systemTemp.createTempSync('convertforall-ui-');
    sourceFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}sample.pdf',
    )..writeAsBytesSync(List<int>.filled(2048, 1));
    engine = RecordingConverterEngine();
    fileActions = RecordingFileActions();
  });

  tearDown(() {
    tempDirectory.deleteSync(recursive: true);
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    bool dragAndDropEnabled = false,
    Size size = const Size(1100, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ConverterPage(
          engine: engine,
          fileActions: fileActions,
          dragAndDropEnabled: dragAndDropEnabled,
          pickInputFile: (_) async => sourceFile.path,
          pickOutputDirectory: () async => tempDirectory.path,
          loadInputFile: (path) async {
            final name = path.replaceAll('\\', '/').split('/').last;
            final extension = name.split('.').last.toLowerCase();
            return SelectedInputFile(
              path: path,
              name: name,
              extension: extension,
              sizeBytes: File(path).lengthSync(),
              sourceFormat: ConversionFormat.fromExtension(extension),
            );
          },
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> settleFileIo(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the minimal initial workflow', (tester) async {
    await pumpPage(tester);

    expect(find.text('convertforall'), findsOneWidget);
    expect(find.text('dosyalarını dönüştür.'), findsOneWidget);
    expect(find.text('hızlı, basit ve tamamen çevrimdışı.'), findsOneWidget);
    expect(find.text('dosya seç'), findsOneWidget);
    expect(find.byKey(const Key('source_format')), findsOneWidget);
    expect(find.byKey(const Key('target_format')), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('convert_button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('selects a PDF and wires conversion and result actions', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('select_file_button')));
    await settleFileIo(tester);

    expect(find.text('sample.pdf'), findsOneWidget);
    expect(find.text('PDF · 2.0 KB'), findsOneWidget);
    expect(find.byKey(const Key('source_format')), findsOneWidget);
    expect(find.byKey(const Key('target_format')), findsOneWidget);
    expect(find.text('kaynak dosyanın klasörü'), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('convert_button')),
    );
    expect(button.onPressed, isNotNull);

    await tester.ensureVisible(find.byKey(const Key('convert_button')));
    await tester.tap(find.byKey(const Key('convert_button')));
    await settleFileIo(tester);

    expect(engine.requests, hasLength(1));
    final request = engine.requests.single;
    expect(request.sourceFormat, ConversionFormat.pdf);
    expect(request.targetFormat, ConversionFormat.docx);
    expect(request.overwrite, isFalse);
    expect(
      request.outputPath,
      '${tempDirectory.path}${Platform.pathSeparator}sample.docx',
    );
    expect(find.text('dönüştürme tamamlandı'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('open_file_button')));
    await tester.tap(find.byKey(const Key('open_file_button')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('reveal_file_button')));
    await tester.tap(find.byKey(const Key('reveal_file_button')));
    await tester.pump();
    expect(fileActions.openedPath, request.outputPath);
    expect(fileActions.revealedPath, request.outputPath);
  });

  testWidgets('accepts a PDF from desktop drag and drop', (tester) async {
    await pumpPage(tester, dragAndDropEnabled: true);
    expect(find.text('dosyanı buraya sürükle'), findsOneWidget);

    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    dropTarget.onDragDone!(
      DropDoneDetails(
        files: [DropItemFile(sourceFile.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await settleFileIo(tester);

    expect(find.text('sample.pdf'), findsOneWidget);
    expect(find.byKey(const Key('target_format')), findsOneWidget);
  });

  testWidgets('rejects an unsupported dropped file', (tester) async {
    final unsupported = File(
      '${tempDirectory.path}${Platform.pathSeparator}notes.txt',
    )..writeAsStringSync('offline');
    await pumpPage(tester, dragAndDropEnabled: true);

    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    dropTarget.onDragDone!(
      DropDoneDetails(
        files: [DropItemFile(unsupported.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await settleFileIo(tester);

    expect(find.textContaining('henüz desteklenmiyor'), findsOneWidget);
    expect(find.byKey(const Key('select_file_button')), findsOneWidget);
  });

  testWidgets('requires confirmation before replacing an output file', (
    tester,
  ) async {
    File(
      '${tempDirectory.path}${Platform.pathSeparator}sample.docx',
    ).writeAsStringSync('existing');
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('select_file_button')));
    await settleFileIo(tester);

    await tester.ensureVisible(find.byKey(const Key('convert_button')));
    await tester.tap(find.byKey(const Key('convert_button')));
    await settleFileIo(tester);

    expect(find.text('Dosyanın üzerine yazılsın mı?'), findsOneWidget);
    expect(engine.requests, isEmpty);

    await tester.tap(find.byKey(const Key('confirm_overwrite_button')));
    await settleFileIo(tester);

    expect(engine.requests.single.overwrite, isTrue);
  });

  testWidgets('keeps the action disabled while conversion is running', (
    tester,
  ) async {
    engine.pendingConversion = Completer<ConversionResult>();
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('select_file_button')));
    await settleFileIo(tester);

    await tester.ensureVisible(find.byKey(const Key('convert_button')));
    await tester.tap(find.byKey(const Key('convert_button')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();

    expect(find.text('dönüştürülüyor…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('convert_button')))
          .onPressed,
      isNull,
    );

    final request = engine.requests.single;
    engine.pendingConversion!.complete(
      ConversionResult(
        success: true,
        message: 'ok',
        durationMs: 20,
        outputPath: request.outputPath,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('dönüştürme tamamlandı'), findsOneWidget);
  });

  testWidgets('does not overflow on a narrow screen', (tester) async {
    await pumpPage(tester, size: const Size(360, 640));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('select_file_button')));
    await settleFileIo(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('sample.pdf'), findsOneWidget);
  });

  testWidgets('shows only worker-reported targets for the selected source', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('select_file_button')));
    await settleFileIo(tester);

    final dropdown = tester.widget<DropdownButton<ConversionFormat>>(
      find.descendant(
        of: find.byKey(const Key('target_format')),
        matching: find.byType(DropdownButton<ConversionFormat>),
      ),
    );
    final values = dropdown.items!
        .map((item) => item.value!.extension)
        .toList();
    expect(values, ['docx', 'txt', 'png', 'jpg', 'jpeg']);
    expect(values, isNot(contains('pdf')));
  });

  testWidgets('selects formats before a file and safely updates targets', (
    tester,
  ) async {
    await pumpPage(tester);

    final sourceDropdown = tester.widget<DropdownButton<ConversionFormat>>(
      find.descendant(
        of: find.byKey(const Key('source_format')),
        matching: find.byType(DropdownButton<ConversionFormat>),
      ),
    );
    expect(sourceDropdown.value, ConversionFormat.pdf);
    sourceDropdown.onChanged!(ConversionFormat.png);
    await tester.pump();

    final changedSource = tester.widget<DropdownButton<ConversionFormat>>(
      find.descendant(
        of: find.byKey(const Key('source_format')),
        matching: find.byType(DropdownButton<ConversionFormat>),
      ),
    );
    final targetDropdown = tester.widget<DropdownButton<ConversionFormat>>(
      find.descendant(
        of: find.byKey(const Key('target_format')),
        matching: find.byType(DropdownButton<ConversionFormat>),
      ),
    );
    expect(changedSource.value, ConversionFormat.png);
    expect(targetDropdown.items!.map((item) => item.value), [
      ConversionFormat.pdf,
      ConversionFormat.jpg,
      ConversionFormat.jpeg,
    ]);
    expect(targetDropdown.value, ConversionFormat.pdf);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('convert_button')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('select_file_button')));
    await settleFileIo(tester);
    final updatedSource = tester.widget<DropdownButton<ConversionFormat>>(
      find.descendant(
        of: find.byKey(const Key('source_format')),
        matching: find.byType(DropdownButton<ConversionFormat>),
      ),
    );
    final updatedTarget = tester.widget<DropdownButton<ConversionFormat>>(
      find.descendant(
        of: find.byKey(const Key('target_format')),
        matching: find.byType(DropdownButton<ConversionFormat>),
      ),
    );
    expect(updatedSource.value, ConversionFormat.pdf);
    expect(updatedTarget.value, ConversionFormat.docx);
  });

  testWidgets('auto-detects JPEG and shows an image icon', (tester) async {
    sourceFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}photo.jpeg',
    )..writeAsBytesSync(List<int>.filled(128, 1));
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('select_file_button')));
    await settleFileIo(tester);

    final sourceDropdown = tester.widget<DropdownButton<ConversionFormat>>(
      find.descendant(
        of: find.byKey(const Key('source_format')),
        matching: find.byType(DropdownButton<ConversionFormat>),
      ),
    );
    expect(sourceDropdown.value, ConversionFormat.jpeg);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);
  });

  testWidgets('shows multiple generated outputs and opens the first one', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('select_file_button')));
    await settleFileIo(tester);
    engine.pendingConversion = Completer<ConversionResult>();

    await tester.ensureVisible(find.byKey(const Key('convert_button')));
    await tester.tap(find.byKey(const Key('convert_button')));
    await tester.pump();
    engine.pendingConversion!.complete(
      ConversionResult(
        success: true,
        message: 'ok',
        durationMs: 25,
        outputPath:
            '${tempDirectory.path}${Platform.pathSeparator}page_001.png',
        outputPaths: [
          '${tempDirectory.path}${Platform.pathSeparator}page_001.png',
          '${tempDirectory.path}${Platform.pathSeparator}page_002.png',
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 dosya hazır · 25 ms'), findsOneWidget);
    expect(find.text('page_001.png'), findsOneWidget);
    expect(find.text('page_002.png'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('open_file_button')));
    await tester.tap(find.byKey(const Key('open_file_button')));
    await tester.pump();
    expect(fileActions.openedPath, endsWith('page_001.png'));
  });
}
