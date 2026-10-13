import 'dart:io';

import 'converter_engine.dart';
import 'desktop_python_converter_engine.dart';
import 'unsupported_converter_engine.dart';

ConverterEngine createPlatformConverterEngine() {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return DesktopPythonConverterEngine();
  }
  return UnsupportedConverterEngine(Platform.operatingSystem);
}
