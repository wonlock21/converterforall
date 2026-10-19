class ConversionFormat {
  const ConversionFormat._(this.extension);

  factory ConversionFormat.fromExtension(String value) {
    final normalized = value.trim().toLowerCase().replaceFirst('.', '');
    if (!RegExp(r'^[a-z0-9]+$').hasMatch(normalized)) {
      throw FormatException('Geçersiz dosya formatı: $value');
    }
    return ConversionFormat._(normalized);
  }

  static const pdf = ConversionFormat._('pdf');
  static const docx = ConversionFormat._('docx');
  static const txt = ConversionFormat._('txt');
  static const jpg = ConversionFormat._('jpg');
  static const jpeg = ConversionFormat._('jpeg');
  static const png = ConversionFormat._('png');

  final String extension;

  @override
  bool operator ==(Object other) =>
      other is ConversionFormat && other.extension == extension;

  @override
  int get hashCode => extension.hashCode;

  @override
  String toString() => extension;
}

class SupportedConversion {
  const SupportedConversion({required this.source, required this.target});

  factory SupportedConversion.fromJson(Map<String, dynamic> json) {
    final source = json['source_format'];
    final target = json['target_format'];
    if (source is! String || target is! String) {
      throw const FormatException('Geçersiz dönüşüm yeteneği.');
    }
    return SupportedConversion(
      source: ConversionFormat.fromExtension(source),
      target: ConversionFormat.fromExtension(target),
    );
  }

  final ConversionFormat source;
  final ConversionFormat target;
}

class ConversionRequest {
  const ConversionRequest({
    required this.inputPath,
    required this.outputPath,
    required this.sourceFormat,
    required this.targetFormat,
    this.overwrite = false,
  });

  final String inputPath;
  final String outputPath;
  final ConversionFormat sourceFormat;
  final ConversionFormat targetFormat;
  final bool overwrite;
}

class ConversionPlan {
  const ConversionPlan({
    required this.success,
    required this.message,
    required this.durationMs,
    this.inputPath,
    this.outputPaths = const [],
    this.conflictingOutputPaths = const [],
    this.errorCode,
  });

  factory ConversionPlan.fromJson(Map<String, dynamic> json) {
    final error = json['error'];
    return ConversionPlan(
      success: json['success'] == true,
      message: json['message'] as String? ?? 'Dönüşüm planı alınamadı.',
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      inputPath: json['input_path'] as String?,
      outputPaths: _stringList(json['output_paths']),
      conflictingOutputPaths: _stringList(json['conflicting_output_paths']),
      errorCode: error is Map<String, dynamic>
          ? error['code'] as String?
          : null,
    );
  }

  final bool success;
  final String message;
  final int durationMs;
  final String? inputPath;
  final List<String> outputPaths;
  final List<String> conflictingOutputPaths;
  final String? errorCode;
}

class ConversionResult {
  const ConversionResult({
    required this.success,
    required this.message,
    required this.durationMs,
    this.inputPath,
    this.outputPath,
    this.outputPaths = const [],
    this.errorCode,
  });

  factory ConversionResult.fromJson(Map<String, dynamic> json) {
    final error = json['error'];
    final legacyOutput = json['output_path'] as String?;
    final outputs = _stringList(json['output_paths']);
    return ConversionResult(
      success: json['success'] == true,
      message: json['message'] as String? ?? 'Dönüştürme sonucu alınamadı.',
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      inputPath: json['input_path'] as String?,
      outputPath: legacyOutput ?? (outputs.isEmpty ? null : outputs.first),
      outputPaths: outputs.isEmpty && legacyOutput != null
          ? [legacyOutput]
          : outputs,
      errorCode: error is Map<String, dynamic>
          ? error['code'] as String?
          : null,
    );
  }

  final bool success;
  final String message;
  final int durationMs;
  final String? inputPath;
  final String? outputPath;
  final List<String> outputPaths;
  final String? errorCode;
}

List<String> _stringList(Object? value) {
  return value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];
}
