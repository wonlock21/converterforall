import 'package:convertforall_flutter/services/conversion_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses successful engine JSON', () {
    final result = ConversionResult.fromJson({
      'success': true,
      'message': 'Conversion completed successfully.',
      'duration_ms': 42,
      'input_path': r'C:\files\input.pdf',
      'output_path': r'C:\files\output.docx',
      'output_paths': [r'C:\files\output.docx'],
      'error': null,
    });

    expect(result.success, isTrue);
    expect(result.durationMs, 42);
    expect(result.outputPath, endsWith('output.docx'));
    expect(result.outputPaths, hasLength(1));
    expect(result.errorCode, isNull);
  });

  test('parses structured engine error', () {
    final result = ConversionResult.fromJson({
      'success': false,
      'message': 'The input file does not exist.',
      'duration_ms': 1,
      'error': {
        'code': 'input_not_found',
        'message': 'The input file does not exist.',
      },
    });

    expect(result.success, isFalse);
    expect(result.errorCode, 'input_not_found');
  });

  test('parses worker-reported conversion capabilities', () {
    final conversion = SupportedConversion.fromJson({
      'source_format': 'PDF',
      'target_format': '.png',
    });

    expect(conversion.source, ConversionFormat.pdf);
    expect(conversion.target, ConversionFormat.png);
  });
}
