import 'dart:io';

abstract interface class FileActions {
  bool get isSupported;

  Future<void> openFile(String path);

  Future<void> revealFile(String path);
}

class FileActionException implements Exception {
  const FileActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DesktopFileActions implements FileActions {
  const DesktopFileActions();

  @override
  bool get isSupported =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Future<void> openFile(String path) async {
    if (Platform.isWindows) {
      await _start('rundll32.exe', ['url.dll,FileProtocolHandler', path]);
    } else if (Platform.isMacOS) {
      await _start('open', [path]);
    } else if (Platform.isLinux) {
      await _start('xdg-open', [path]);
    } else {
      throw const FileActionException('Bu platformda dosya açılamıyor.');
    }
  }

  @override
  Future<void> revealFile(String path) async {
    if (Platform.isWindows) {
      await _start('explorer.exe', ['/select,$path']);
    } else if (Platform.isMacOS) {
      await _start('open', ['-R', path]);
    } else if (Platform.isLinux) {
      await _start('xdg-open', [File(path).parent.path]);
    } else {
      throw const FileActionException('Bu platformda klasör açılamıyor.');
    }
  }

  static Future<void> _start(String executable, List<String> arguments) async {
    try {
      await Process.start(
        executable,
        arguments,
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (error) {
      throw FileActionException('İşlem başlatılamadı: ${error.message}');
    }
  }
}
