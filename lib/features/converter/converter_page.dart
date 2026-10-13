import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/conversion_models.dart';
import '../../services/converter_engine.dart';

class ConverterPage extends StatefulWidget {
  const ConverterPage({required this.engine, super.key});

  final ConverterEngine engine;

  @override
  State<ConverterPage> createState() => _ConverterPageState();
}

class _ConverterPageState extends State<ConverterPage> {
  String? _inputPath;
  String? _outputDirectory;
  ConversionFormat _targetFormat = ConversionFormat.docx;
  bool _overwrite = false;
  bool _isConverting = false;
  ConversionResult? _lastResult;

  @override
  void dispose() {
    unawaited(widget.engine.close());
    super.dispose();
  }

  String? get _outputPath {
    final inputPath = _inputPath;
    final outputDirectory = _outputDirectory;
    if (inputPath == null || outputDirectory == null) {
      return null;
    }
    final normalized = inputPath.replaceAll('\\', '/');
    final fileName = normalized.substring(normalized.lastIndexOf('/') + 1);
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    return '$outputDirectory${Platform.pathSeparator}'
        '$baseName.${_targetFormat.extension}';
  }

  Future<void> _chooseInput() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Dönüştürülecek PDF dosyasını seçin',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (file?.path == null || !mounted) {
      return;
    }
    setState(() {
      _inputPath = file!.path;
      _lastResult = null;
    });
  }

  Future<void> _chooseOutputDirectory() async {
    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: 'DOCX dosyasının kaydedileceği klasörü seçin',
    );
    if (directory == null || !mounted) {
      return;
    }
    setState(() {
      _outputDirectory = directory;
      _lastResult = null;
    });
  }

  Future<void> _convert() async {
    final outputPath = _outputPath;
    final inputPath = _inputPath;
    if (inputPath == null || outputPath == null || _isConverting) {
      return;
    }

    setState(() {
      _isConverting = true;
      _lastResult = null;
    });

    try {
      final result = await widget.engine.convert(
        ConversionRequest(
          inputPath: inputPath,
          outputPath: outputPath,
          sourceFormat: ConversionFormat.pdf,
          targetFormat: _targetFormat,
          overwrite: _overwrite,
        ),
      );
      if (!mounted) return;
      setState(() => _lastResult = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? 'Dönüştürme tamamlandı.'
                : 'Dönüştürme başarısız: ${result.message}',
          ),
        ),
      );
    } on ConverterEngineException catch (error) {
      if (!mounted) return;
      final result = ConversionResult(
        success: false,
        message: error.message,
        durationMs: 0,
        inputPath: inputPath,
        outputPath: outputPath,
        errorCode: 'engine_unavailable',
      );
      setState(() => _lastResult = result);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      const message = 'Beklenmeyen bir hata oluştu.';
      setState(
        () => _lastResult = ConversionResult(
          success: false,
          message: '$message ($error)',
          durationMs: 0,
          inputPath: inputPath,
          outputPath: outputPath,
          errorCode: 'unexpected_error',
        ),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isConverting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canConvert =
        _inputPath != null &&
        _outputDirectory != null &&
        !_isConverting &&
        widget.engine.supports(ConversionFormat.pdf, _targetFormat);

    return Scaffold(
      appBar: AppBar(title: const Text('Universal Converter')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'PDF → DOCX',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Dosyalarınız cihazınızdan ayrılmadan dönüştürülür.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 28),
                    _PathField(
                      label: 'Kaynak PDF',
                      value: _inputPath,
                      buttonLabel: 'PDF seç',
                      icon: Icons.picture_as_pdf_outlined,
                      onPressed: _isConverting ? null : _chooseInput,
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<ConversionFormat>(
                      initialValue: _targetFormat,
                      decoration: const InputDecoration(
                        labelText: 'Çıktı formatı',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ConversionFormat.docx,
                          child: Text('DOCX'),
                        ),
                      ],
                      onChanged: _isConverting
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _targetFormat = value);
                              }
                            },
                    ),
                    const SizedBox(height: 20),
                    _PathField(
                      label: 'Çıktı klasörü',
                      value: _outputDirectory,
                      buttonLabel: 'Klasör seç',
                      icon: Icons.folder_outlined,
                      onPressed: _isConverting ? null : _chooseOutputDirectory,
                    ),
                    if (_outputPath != null) ...[
                      const SizedBox(height: 12),
                      SelectableText('Çıktı: $_outputPath'),
                    ],
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _overwrite,
                      title: const Text('Aynı adlı dosya varsa üzerine yaz'),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: _isConverting
                          ? null
                          : (value) =>
                                setState(() => _overwrite = value ?? false),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('convert_button'),
                      onPressed: canConvert ? _convert : null,
                      icon: _isConverting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(
                        _isConverting
                            ? 'Dönüştürülüyor…'
                            : 'Dönüştürmeyi başlat',
                      ),
                    ),
                    if (_lastResult case final result?) ...[
                      const SizedBox(height: 20),
                      _ResultPanel(result: result),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PathField extends StatelessWidget {
  const _PathField({
    required this.label,
    required this.value,
    required this.buttonLabel,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String? value;
  final String buttonLabel;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value ?? 'Henüz seçilmedi',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(onPressed: onPressed, child: Text(buttonLabel)),
        ],
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result});

  final ConversionResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.success
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.errorContainer;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            result.success ? Icons.check_circle_outline : Icons.error_outline,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              result.success
                  ? 'Başarılı (${result.durationMs} ms)\n${result.outputPath}'
                  : result.message,
            ),
          ),
        ],
      ),
    );
  }
}
