import 'conversion_models.dart';

abstract interface class ConverterEngine {
  bool supports(ConversionFormat source, ConversionFormat target);

  Future<ConversionResult> convert(ConversionRequest request);

  Future<void> close();
}

class ConverterEngineException implements Exception {
  const ConverterEngineException(this.message);

  final String message;

  @override
  String toString() => message;
}
