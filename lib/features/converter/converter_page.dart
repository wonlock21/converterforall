import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/conversion_models.dart';
import '../../services/converter_engine.dart';
import '../../services/file_actions.dart';
import 'models/selected_input_file.dart';
import 'widgets/converter_card.dart';
import 'widgets/converter_page_header.dart';

typedef InputFilePicker = Future<String?> Function(List<String> extensions);
typedef OutputDirectoryPicker = Future<String?> Function();
typedef InputFileLoader = Future<SelectedInputFile?> Function(String path);

Future<String?> _pickInputFile(List<String> extensions) async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Dönüştürülecek dosyayı seçin',
    type: FileType.custom,
    allowedExtensions: extensions,
  );
  return file?.path;
}

Future<String?> _pickOutputDirectory() {
  return FilePicker.getDirectoryPath(dialogTitle: 'Çıktı klasörünü seçin');
}

class ConverterPage extends StatefulWidget {
  const ConverterPage({
    required this.engine,
    this.onThemeToggle,
    this.isDarkMode = false,
    this.pickInputFile = _pickInputFile,
    this.pickOutputDirectory = _pickOutputDirectory,
    this.loadInputFile = SelectedInputFile.fromPath,
    this.fileActions = const DesktopFileActions(),
    this.dragAndDropEnabled,
    super.key,
  });

  final ConverterEngine engine;
  final VoidCallback? onThemeToggle;
  final bool isDarkMode;
  final InputFilePicker pickInputFile;
  final OutputDirectoryPicker pickOutputDirectory;
  final InputFileLoader loadInputFile;
  final FileActions fileActions;
  final bool? dragAndDropEnabled;

  @override
  State<ConverterPage> createState() => _ConverterPageState();
}

class _ConverterPageState extends State<ConverterPage> {
  SelectedInputFile? _inputFile;
  String? _outputDirectory;
  ConversionFormat? _sourceFormat = ConversionFormat.pdf;
  ConversionFormat? _targetFormat = ConversionFormat.docx;
  bool _usesSourceDirectory = true;
  bool _overwrite = false;
  bool _isConverting = false;
  ConversionResult? _lastResult;
  List<SupportedConversion> _supportedConversions = const [];
  bool _isLoadingCapabilities = true;

  bool get _canDropFiles =>
      widget.dragAndDropEnabled ??
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  List<ConversionFormat> get _supportedSourceFormats {
    return _supportedConversions
        .map((conversion) => conversion.source)
        .toSet()
        .toList(growable: false);
  }

  List<ConversionFormat> get _availableTargets {
    final source = _sourceFormat;
    if (source == null) return const [];
    return _supportedConversions
        .where((conversion) => conversion.source == source)
        .map((conversion) => conversion.target)
        .toList(growable: false);
  }

  String? get _outputPath {
    final input = _inputFile;
    final directory = _outputDirectory;
    final target = _targetFormat;
    if (input == null || directory == null || target == null) return null;
    return '$directory${Platform.pathSeparator}'
        '${input.baseName}.${target.extension}';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadCapabilities());
  }

  Future<void> _loadCapabilities() async {
    try {
      final conversions = await widget.engine.getSupportedConversions();
      if (!mounted) return;
      setState(() {
        _supportedConversions = conversions;
        _isLoadingCapabilities = false;
        final sources = _supportedSourceFormats;
        _sourceFormat = sources.contains(_sourceFormat)
            ? _sourceFormat
            : (sources.isEmpty ? null : sources.first);
        final targets = _availableTargets;
        _targetFormat = targets.contains(_targetFormat)
            ? _targetFormat
            : (targets.isEmpty ? null : targets.first);
        if (conversions.isEmpty) {
          _lastResult = const ConversionResult(
            success: false,
            message: 'Bu platformda kullanılabilir bir dönüşüm bulunamadı.',
            durationMs: 0,
            errorCode: 'no_supported_conversions',
          );
        }
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingCapabilities = false;
        _lastResult = ConversionResult(
          success: false,
          message: 'Dönüştürme motoru başlatılamadı: $error',
          durationMs: 0,
          errorCode: 'engine_unavailable',
        );
      });
    }
  }

  @override
  void dispose() {
    unawaited(widget.engine.close());
    super.dispose();
  }

  Future<void> _chooseInput() async {
    if (_supportedSourceFormats.isEmpty) {
      _showMessage('Bu platformda kullanılabilir bir dönüştürme motoru yok.');
      return;
    }
    final path = await widget.pickInputFile(_inputPickerExtensions);
    if (path != null && mounted) await _selectInput(path);
  }

  List<String> get _inputPickerExtensions {
    final source = _sourceFormat;
    if (source == ConversionFormat.jpg || source == ConversionFormat.jpeg) {
      return const ['jpg', 'jpeg'];
    }
    if (source != null && _supportedSourceFormats.contains(source)) {
      return [source.extension];
    }
    return _supportedSourceFormats
        .map((format) => format.extension)
        .toList(growable: false);
  }

  Future<void> _selectInput(String path) async {
    if (_isConverting) return;
    final selected = await widget.loadInputFile(path);
    if (!mounted) return;

    if (selected == null ||
        !_supportedSourceFormats.contains(selected.sourceFormat)) {
      _showMessage('Bu dosya türü henüz desteklenmiyor.');
      return;
    }
    final targets = _supportedConversions
        .where((conversion) => conversion.source == selected.sourceFormat)
        .map((conversion) => conversion.target)
        .toList();
    if (targets.isEmpty) {
      _showMessage('Bu dosya için kullanılabilir bir hedef format bulunamadı.');
      return;
    }

    setState(() {
      _inputFile = selected;
      _sourceFormat = selected.sourceFormat;
      _targetFormat = targets.contains(_targetFormat)
          ? _targetFormat
          : targets.first;
      _outputDirectory = selected.directoryPath;
      _usesSourceDirectory = true;
      _overwrite = false;
      _lastResult = null;
    });
  }

  void _removeInput() {
    if (_isConverting) return;
    setState(() {
      _inputFile = null;
      _outputDirectory = null;
      _usesSourceDirectory = true;
      _overwrite = false;
      _lastResult = null;
    });
  }

  void _changeSourceFormat(ConversionFormat format) {
    if (_isConverting || format == _sourceFormat) return;
    final targets = _supportedConversions
        .where((conversion) => conversion.source == format)
        .map((conversion) => conversion.target)
        .toList(growable: false);
    final inputIsIncompatible =
        _inputFile != null && _inputFile!.sourceFormat != format;
    setState(() {
      _sourceFormat = format;
      _targetFormat = targets.contains(_targetFormat)
          ? _targetFormat
          : (targets.isEmpty ? null : targets.first);
      if (inputIsIncompatible) {
        _inputFile = null;
        _outputDirectory = null;
        _usesSourceDirectory = true;
        _overwrite = false;
      }
      _lastResult = null;
    });
  }

  void _changeTargetFormat(ConversionFormat format) {
    if (_isConverting || !_availableTargets.contains(format)) return;
    setState(() {
      _targetFormat = format;
      _lastResult = null;
    });
  }

  Future<void> _chooseOutputDirectory() async {
    final directory = await widget.pickOutputDirectory();
    if (directory == null || !mounted) return;
    setState(() {
      _outputDirectory = directory;
      _usesSourceDirectory = directory == _inputFile?.directoryPath;
      _lastResult = null;
    });
  }

  Future<bool> _confirmOverwrite(List<String> conflictingPaths) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          conflictingPaths.length == 1
              ? 'Dosyanın üzerine yazılsın mı?'
              : 'Dosyaların üzerine yazılsın mı?',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Aşağıdaki dosyalar zaten var. Onaylarsanız yalnızca bu dönüşüm için üzerlerine yazılacak:',
              ),
              const SizedBox(height: 12),
              for (final path in conflictingPaths)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• ${_fileName(path)}'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('vazgeç'),
          ),
          FilledButton(
            key: const Key('confirm_overwrite_button'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('üzerine yaz'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _convert() async {
    final outputPath = _outputPath;
    final input = _inputFile;
    final target = _targetFormat;
    if (input == null ||
        outputPath == null ||
        target == null ||
        _isConverting) {
      return;
    }

    setState(() {
      _isConverting = true;
      _lastResult = null;
    });

    try {
      final baseRequest = ConversionRequest(
        inputPath: input.path,
        outputPath: outputPath,
        sourceFormat: input.sourceFormat,
        targetFormat: target,
      );
      final plan = await widget.engine.planConversion(baseRequest);
      if (!mounted) return;
      if (!plan.success) {
        final message = _localizedError(plan.errorCode, plan.message);
        setState(
          () => _lastResult = ConversionResult(
            success: false,
            message: message,
            durationMs: plan.durationMs,
            inputPath: input.path,
            outputPath: outputPath,
            errorCode: plan.errorCode,
          ),
        );
        _showMessage(message);
        return;
      }

      var oneTimeOverwriteApproval = false;
      if (plan.conflictingOutputPaths.isNotEmpty) {
        oneTimeOverwriteApproval = await _confirmOverwrite(
          plan.conflictingOutputPaths,
        );
        if (!oneTimeOverwriteApproval || !mounted) return;
      }

      final result = await widget.engine.convert(
        ConversionRequest(
          inputPath: input.path,
          outputPath: outputPath,
          sourceFormat: input.sourceFormat,
          targetFormat: target,
          overwrite: _overwrite || oneTimeOverwriteApproval,
        ),
      );
      if (!mounted) return;
      final displayedResult = result.success
          ? result
          : ConversionResult(
              success: false,
              message: _localizedError(result.errorCode, result.message),
              durationMs: result.durationMs,
              inputPath: result.inputPath,
              outputPath: result.outputPath,
              outputPaths: result.outputPaths,
              errorCode: result.errorCode,
            );
      setState(() => _lastResult = displayedResult);
      _showMessage(
        result.success
            ? 'Dönüştürme tamamlandı.'
            : 'Dönüştürme başarısız: ${displayedResult.message}',
      );
    } on ConverterEngineException catch (error) {
      if (!mounted) return;
      setState(
        () => _lastResult = ConversionResult(
          success: false,
          message: error.message,
          durationMs: 0,
          inputPath: input.path,
          outputPath: outputPath,
          errorCode: 'engine_unavailable',
        ),
      );
      _showMessage(error.message);
    } catch (error) {
      if (!mounted) return;
      const message = 'Beklenmeyen bir hata oluştu.';
      setState(
        () => _lastResult = ConversionResult(
          success: false,
          message: '$message ($error)',
          durationMs: 0,
          inputPath: input.path,
          outputPath: outputPath,
          errorCode: 'unexpected_error',
        ),
      );
      _showMessage(message);
    } finally {
      if (mounted) setState(() => _isConverting = false);
    }
  }

  Future<void> _runFileAction(Future<void> Function(String path) action) async {
    final outputs = _lastResult?.outputPaths ?? const <String>[];
    final path = outputs.isNotEmpty
        ? outputs.first
        : (_lastResult?.outputPath ?? _outputPath);
    if (path == null) return;
    try {
      await action(path);
    } on FileActionException catch (error) {
      if (mounted) _showMessage(error.message);
    } on Object {
      if (mounted) _showMessage('Dosya işlemi başlatılamadı.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final input = _inputFile;
    final outputDirectory = _outputDirectory;
    final targets = _availableTargets;
    final canConvert =
        input != null &&
        input.sourceFormat == _sourceFormat &&
        outputDirectory != null &&
        _targetFormat != null &&
        targets.contains(_targetFormat) &&
        !_isConverting;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final horizontalPadding = compact ? 16.0 : 28.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                compact ? 14 : 22,
                horizontalPadding,
                36,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConverterPageHeader(
                    compact: compact,
                    isDarkMode: widget.isDarkMode,
                    onThemeToggle: widget.onThemeToggle,
                  ),
                  SizedBox(height: compact ? 26 : 34),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: ConverterCard(
                        compact: compact,
                        inputFile: input,
                        availableSources: _supportedSourceFormats,
                        sourceFormat: _sourceFormat,
                        availableTargets: targets,
                        targetFormat: _targetFormat,
                        outputDirectory: outputDirectory,
                        outputDirectoryName: outputDirectory == null
                            ? null
                            : _directoryName(outputDirectory),
                        usesSourceDirectory: _usesSourceDirectory,
                        overwrite: _overwrite,
                        isConverting: _isConverting,
                        isLoadingFormats: _isLoadingCapabilities,
                        canConvert: canConvert,
                        canSelectFiles:
                            !_isConverting &&
                            !_isLoadingCapabilities &&
                            _supportedSourceFormats.isNotEmpty,
                        dragAndDropEnabled: _canDropFiles,
                        result: _lastResult,
                        onChooseFile: _chooseInput,
                        onFileDropped: _selectInput,
                        onRemoveFile: _removeInput,
                        onSourceChanged: _changeSourceFormat,
                        onTargetChanged: _changeTargetFormat,
                        onChooseOutputDirectory: _chooseOutputDirectory,
                        onOverwriteChanged: (value) => setState(() {
                          _overwrite = value;
                          _lastResult = null;
                        }),
                        onConvert: _convert,
                        onOpenFile:
                            _lastResult?.success == true &&
                                widget.fileActions.isSupported
                            ? () => _runFileAction(widget.fileActions.openFile)
                            : null,
                        onRevealFile:
                            _lastResult?.success == true &&
                                widget.fileActions.isSupported
                            ? () =>
                                  _runFileAction(widget.fileActions.revealFile)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Text(
                      'dosyaların cihazından ayrılmaz',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static String _directoryName(String path) {
    final normalized = path
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/$'), '');
    final name = normalized.substring(normalized.lastIndexOf('/') + 1);
    return name.isEmpty ? path : name;
  }

  static String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  static String _localizedError(String? code, String fallback) {
    return switch (code) {
      'input_not_found' => 'Seçilen giriş dosyası bulunamadı.',
      'invalid_pdf' => 'Seçilen dosya geçerli bir PDF değil.',
      'empty_pdf' => 'PDF dosyasında dönüştürülecek sayfa bulunmuyor.',
      'password_protected_pdf' =>
        'Parola korumalı PDF dosyaları desteklenmiyor.',
      'invalid_image' || 'invalid_image_format' =>
        'Seçilen dosya geçerli veya desteklenen bir görsel değil.',
      'no_extractable_text' =>
        'PDF içinde seçilebilir metin bulunamadı. OCR henüz desteklenmiyor.',
      'output_exists' =>
        'Bir çıktı dosyası işlem sırasında oluşturuldu. Dosyaya dokunulmadı; yeniden deneyin.',
      'output_directory_not_found' => 'Seçilen çıktı klasörü bulunamadı.',
      'output_directory_not_writable' => 'Seçilen çıktı klasörüne yazılamıyor.',
      'output_not_file' => 'Çıktı yolunda aynı adlı bir klasör bulunuyor.',
      'same_input_output' => 'Giriş ve çıktı dosyası aynı olamaz.',
      'unsupported_conversion' => 'Bu dönüşüm türü desteklenmiyor.',
      'empty_output' || 'invalid_converter_output' =>
        'Dönüştürücü geçerli bir çıktı oluşturamadı.',
      'pdf_to_docx_failed' ||
      'pdf_to_text_failed' ||
      'pdf_to_image_failed' ||
      'image_to_pdf_failed' ||
      'image_conversion_failed' => 'Dosya dönüştürülürken bir hata oluştu.',
      'internal_error' => 'Dönüştürme sırasında beklenmeyen bir hata oluştu.',
      _ => fallback,
    };
  }
}
