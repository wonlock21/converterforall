import 'conversion_models.dart';
import 'converter_engine.dart';

class UnsupportedConverterEngine implements ConverterEngine {
  const UnsupportedConverterEngine(this.platformName);

  final String platformName;

  @override
  Future<List<SupportedConversion>> getSupportedConversions() async => const [];

  @override
  Future<void> close() async {}

  @override
  Future<ConversionPlan> planConversion(ConversionRequest request) async {
    return ConversionPlan(
      success: false,
      message: '$platformName için dönüştürme motoru henüz eklenmedi.',
      durationMs: 0,
      inputPath: request.inputPath,
      errorCode: 'platform_not_supported',
    );
  }

  @override
  Future<ConversionResult> convert(ConversionRequest request) async {
    return ConversionResult(
      success: false,
      message: '$platformName için dönüştürme motoru henüz eklenmedi.',
      durationMs: 0,
      inputPath: request.inputPath,
      outputPath: request.outputPath,
      errorCode: 'platform_not_supported',
    );
  }
}
