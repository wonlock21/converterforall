import 'dart:io';

import 'converter_engine.dart';
import 'unsupported_converter_engine.dart';
import 'windows_python_converter_engine.dart';

ConverterEngine createPlatformConverterEngine() {
  if (Platform.isWindows) {
    return WindowsPythonConverterEngine();
  }
  return UnsupportedConverterEngine(Platform.operatingSystem);
}
