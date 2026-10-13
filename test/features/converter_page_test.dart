import 'package:convertforall_flutter/features/converter/converter_page.dart';
import 'package:convertforall_flutter/services/conversion_models.dart';
import 'package:convertforall_flutter/services/converter_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeConverterEngine implements ConverterEngine {
  @override
  Future<void> close() async {}

  @override
  Future<ConversionResult> convert(ConversionRequest request) async {
    return const ConversionResult(success: true, message: 'ok', durationMs: 1);
  }

  @override
  bool supports(ConversionFormat source, ConversionFormat target) => true;
}

void main() {
  testWidgets('shows the initial PDF to DOCX workflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ConverterPage(engine: FakeConverterEngine())),
    );

    expect(find.text('PDF → DOCX'), findsOneWidget);
    expect(find.text('PDF seç'), findsOneWidget);
    expect(find.text('Klasör seç'), findsOneWidget);
    expect(find.text('Dönüştürmeyi başlat'), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('convert_button')),
    );
    expect(button.onPressed, isNull);
  });
}
