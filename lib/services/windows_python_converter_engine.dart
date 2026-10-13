import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'conversion_models.dart';
import 'converter_engine.dart';

typedef ProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    });

class WindowsPythonConverterEngine implements ConverterEngine {
  WindowsPythonConverterEngine({
    String? pythonExecutable,
    String? projectRoot,
    Map<String, String>? environment,
    ProcessStarter? processStarter,
  }) : _projectRoot = projectRoot ?? _findProjectRoot(),
       _configuredPythonExecutable = pythonExecutable,
       _environment = environment,
       _processStarter = processStarter ?? Process.start;

  final String _projectRoot;
  final String? _configuredPythonExecutable;
  final Map<String, String>? _environment;
  final ProcessStarter _processStarter;
  final Map<String, Completer<ConversionResult>> _pendingRequests = {};
  final List<String> _recentErrorLines = [];

  Process? _process;
  Future<Process>? _startingProcess;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Future<void> _writeQueue = Future<void>.value();
  int _requestSequence = 0;
  bool _closed = false;

  @override
  bool supports(ConversionFormat source, ConversionFormat target) {
    return source == ConversionFormat.pdf && target == ConversionFormat.docx;
  }

  @override
  Future<ConversionResult> convert(ConversionRequest request) async {
    if (!supports(request.sourceFormat, request.targetFormat)) {
      return const ConversionResult(
        success: false,
        message: 'Bu dönüşüm türü desteklenmiyor.',
        durationMs: 0,
        errorCode: 'unsupported_conversion',
      );
    }

    final process = await _ensureProcess();
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${++_requestSequence}';
    final completer = Completer<ConversionResult>();
    _pendingRequests[requestId] = completer;

    final message = <String, Object>{
      'id': requestId,
      'action': 'convert',
      'source_format': request.sourceFormat.extension,
      'target_format': request.targetFormat.extension,
      'input_path': request.inputPath,
      'output_path': request.outputPath,
      'overwrite': request.overwrite,
    };

    try {
      await _enqueueMessage(process, message);
    } on Object catch (error) {
      _pendingRequests.remove(requestId);
      throw ConverterEngineException(
        'Dönüştürme isteği Python motoruna gönderilemedi: $error',
      );
    }

    return completer.future;
  }

  Future<void> _enqueueMessage(Process process, Map<String, Object> message) {
    final write = _writeQueue.then((_) async {
      if (!identical(_process, process)) {
        throw const ConverterEngineException(
          'Python motoru istek gönderilmeden önce kapandı.',
        );
      }
      process.stdin.writeln(jsonEncode(message));
      await process.stdin.flush();
    });
    _writeQueue = write.catchError((Object _) {});
    return write;
  }

  Future<Process> _ensureProcess() async {
    if (_closed) {
      throw const ConverterEngineException(
        'Dönüştürme motoru daha önce kapatıldı.',
      );
    }
    final runningProcess = _process;
    if (runningProcess != null) {
      return runningProcess;
    }
    final currentStart = _startingProcess;
    if (currentStart != null) {
      return currentStart;
    }

    final start = _startProcess();
    _startingProcess = start;
    try {
      return await start;
    } on ProcessException catch (error) {
      throw ConverterEngineException(
        'Python motoru başlatılamadı (${error.message}). '
        'Python ortamını ve backend bağımlılıklarını kontrol edin.',
      );
    } finally {
      if (identical(_startingProcess, start)) {
        _startingProcess = null;
      }
    }
  }

  Future<Process> _startProcess() async {
    final executable =
        _configuredPythonExecutable ??
        Platform.environment['UNIVERSAL_CONVERTER_PYTHON'] ??
        _discoverPythonExecutable(_projectRoot);
    final process = await _processStarter(
      executable,
      const ['-m', 'backend.worker'],
      workingDirectory: _projectRoot,
      environment: _environment,
    );
    _process = process;
    _recentErrorLines.clear();
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleProtocolLine, onError: _handleProtocolStreamError);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleErrorLine);
    unawaited(_watchProcess(process));
    return process;
  }

  void _handleProtocolLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON object expected');
      }

      final requestId = decoded['id'];
      if (requestId == null) {
        final message =
            decoded['message'] as String? ??
            'Python motoru beklenmeyen şekilde durdu.';
        _failAll(ConverterEngineException(message));
        return;
      }
      if (requestId is! String) {
        throw const FormatException('String request id expected');
      }

      final completer = _pendingRequests.remove(requestId);
      if (completer == null) {
        developer.log(
          'Bilinmeyen Python yanıt kimliği: $requestId',
          name: 'universal_converter.worker',
        );
        return;
      }
      completer.complete(ConversionResult.fromJson(decoded));
    } on Object catch (error, stackTrace) {
      _handleProtocolFailure(error, stackTrace);
    }
  }

  void _handleProtocolStreamError(Object error, StackTrace stackTrace) {
    _handleProtocolFailure(error, stackTrace);
  }

  void _handleProtocolFailure(Object error, StackTrace stackTrace) {
    developer.log(
      'Python motorundan geçersiz protokol mesajı alındı.',
      name: 'universal_converter.worker',
      error: error,
      stackTrace: stackTrace,
    );
    _failAll(
      const ConverterEngineException(
        'Python motorundan geçersiz bir yanıt alındı.',
      ),
    );
    _process?.kill();
  }

  void _handleErrorLine(String line) {
    if (line.trim().isEmpty) {
      return;
    }
    _recentErrorLines.add(line);
    if (_recentErrorLines.length > 20) {
      _recentErrorLines.removeAt(0);
    }
    developer.log(line, name: 'universal_converter.worker');
  }

  Future<void> _watchProcess(Process process) async {
    final exitCode = await process.exitCode;
    if (!identical(_process, process)) {
      return;
    }
    _process = null;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    if (!_closed) {
      final detail = _recentErrorLines.isEmpty
          ? ''
          : ' Son motor mesajı: ${_recentErrorLines.last}';
      _failAll(
        ConverterEngineException(
          'Python motoru beklenmeyen şekilde kapandı '
          '(çıkış kodu $exitCode).$detail',
        ),
      );
    }
  }

  void _failAll(ConverterEngineException error) {
    final completers = _pendingRequests.values.toList();
    _pendingRequests.clear();
    for (final completer in completers) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _failAll(const ConverterEngineException('Dönüştürme motoru kapatıldı.'));

    Process? process = _process;
    if (process == null && _startingProcess != null) {
      try {
        process = await _startingProcess;
      } on Object {
        process = null;
      }
    }
    if (process != null) {
      try {
        await _writeQueue;
        await process.stdin.close();
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill();
      } on Object {
        process.kill();
      }
    }
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _process = null;
  }

  static String _discoverPythonExecutable(String projectRoot) {
    final candidates = <String>[
      '$projectRoot${Platform.pathSeparator}.venv${Platform.pathSeparator}'
          'Scripts${Platform.pathSeparator}python.exe',
      '$projectRoot${Platform.pathSeparator}.venv${Platform.pathSeparator}'
          'bin${Platform.pathSeparator}python.exe',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return 'python';
  }

  static String _findProjectRoot() {
    final configured = Platform.environment['UNIVERSAL_CONVERTER_PROJECT_ROOT'];
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }

    for (final start in <String>[
      Directory.current.path,
      File(Platform.resolvedExecutable).parent.path,
    ]) {
      var directory = Directory(start).absolute;
      for (var depth = 0; depth < 8; depth++) {
        final worker = File(
          '${directory.path}${Platform.pathSeparator}backend'
          '${Platform.pathSeparator}worker.py',
        );
        if (worker.existsSync()) {
          return directory.path;
        }
        final parent = directory.parent;
        if (parent.path == directory.path) {
          break;
        }
        directory = parent;
      }
    }
    return Directory.current.path;
  }
}
