enum ConversionFormat {
  pdf('pdf'),
  docx('docx');

  const ConversionFormat(this.extension);

  final String extension;
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

class ConversionResult {
  const ConversionResult({
    required this.success,
    required this.message,
    required this.durationMs,
    this.inputPath,
    this.outputPath,
    this.errorCode,
  });

  factory ConversionResult.fromJson(Map<String, dynamic> json) {
    final error = json['error'];
    return ConversionResult(
      success: json['success'] == true,
      message: json['message'] as String? ?? 'Dönüştürme sonucu alınamadı.',
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      inputPath: json['input_path'] as String?,
      outputPath: json['output_path'] as String?,
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
  final String? errorCode;
}
