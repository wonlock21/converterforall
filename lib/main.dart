import 'package:flutter/material.dart';

import 'features/converter/converter_page.dart';
import 'services/converter_engine.dart';
import 'services/platform_converter_engine.dart';

void main() {
  runApp(MainApp());
}

class MainApp extends StatelessWidget {
  MainApp({super.key, ConverterEngine? engine})
    : engine = engine ?? createPlatformConverterEngine();

  final ConverterEngine engine;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Universal Converter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4054B2)),
        useMaterial3: true,
      ),
      home: ConverterPage(engine: engine),
    );
  }
}
