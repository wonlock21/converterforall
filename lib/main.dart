import 'package:flutter/material.dart';

import 'features/converter/converter_page.dart';
import 'services/converter_engine.dart';
import 'services/platform_converter_engine.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(MainApp());
}

class MainApp extends StatefulWidget {
  MainApp({super.key, ConverterEngine? engine})
    : engine = engine ?? createPlatformConverterEngine();

  final ConverterEngine engine;

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'convertforall',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      home: ConverterPage(
        engine: widget.engine,
        isDarkMode: _themeMode == ThemeMode.dark,
        onThemeToggle: () {
          setState(() {
            _themeMode = _themeMode == ThemeMode.dark
                ? ThemeMode.light
                : ThemeMode.dark;
          });
        },
      ),
    );
  }
}
