import 'package:convertforall_flutter/main.dart';
import 'package:convertforall_flutter/services/conversion_models.dart';
import 'package:convertforall_flutter/services/converter_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThemeTestEngine implements ConverterEngine {
  @override
  Future<void> close() async {}

  @override
  Future<ConversionResult> convert(ConversionRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<ConversionPlan> planConversion(ConversionRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<List<SupportedConversion>> getSupportedConversions() async => const [
    SupportedConversion(
      source: ConversionFormat.pdf,
      target: ConversionFormat.docx,
    ),
  ];
}

void main() {
  testWidgets('toggles between the centralized light and dark themes', (
    tester,
  ) async {
    await tester.pumpWidget(MainApp(engine: _ThemeTestEngine()));
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );

    await tester.tap(find.byKey(const Key('theme_toggle_button')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(find.text('convertforall'), findsOneWidget);
  });
}
