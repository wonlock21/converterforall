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

class _WorkerLaunchConfiguration {
  const _WorkerLaunchConfiguration({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
}

class DesktopPythonConverterEngine implements ConverterEngine {
  DesktopPythonConverterEngine({
    String? workerExecutable,
    String? pythonExecutable,
    String? projectRoot,
    Map<String, String>? environment,
    ProcessStarter? processStarter,
    bool? isRelease,
  }) : _configuredWorkerExecutable = workerExecutable,
       _configuredPythonExecutable = pythonExecutable,
       _projectRoot = projectRoot ?? _findProjectRoot(),
       _environment = environment,
       _processStarter = processStarter ?? Process.start,
       _isRelease = isRelease ?? const bool.fromEnvironment('dart.vm.product');

  final String? _configuredWorkerExecutable;
  final String? _configuredPythonExecutable;
  final String _projectRoot;
  final Map<String, String>? _environment;
  final ProcessStarter _processStarter;
  final bool _isRelease;
  final Map<String, Completer<ConversionResult>> _pendingRequests = {};
  final Map<String, Completer<ConversionPlan>> _pendingPlanRequests = {};
  final Map<String, Completer<List<SupportedConversion>>>
  _pendingCapabilityRequests = {};
  final List<String> _recentErrorLines = [];

  Process? _process;
  Future<Process>? _startingProcess;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Future<void> _writeQueue = Future<void>.value();
  int _requestSequence = 0;
  bool _closed = false;
  Future<List<SupportedConversion>>? _capabilities;

  @override
  Future<List<SupportedConversion>> getSupportedConversions() {
    final cached = _capabilities;
    if (cached != null) return cached;
    final request = _requestCapabilities();
    _capabilities = request;
    request.catchError((Object _) {
      if (identical(_capabilities, request)) _capabilities = null;
      return <SupportedConversion>[];
    });
    return request;
  }

  Future<List<SupportedConversion>> _requestCapabilities() async {
    final process = await _ensureProcess();
    final requestId = _nextRequestId();
    final completer = Completer<List<SupportedConversion>>();
    _pendingCapabilityRequests[requestId] = completer;
    try {
      await _enqueueMessage(process, {
        'id': requestId,
        'action': 'capabilities',
      });
    } on Object catch (error) {
      _pendingCapabilityRequests.remove(requestId);
      throw ConverterEngineException(
        'Desteklenen formatlar yerel motordan alınamadı: $error',
      );
    }
    return completer.future;
  }

  @override
  Future<ConversionResult> convert(ConversionRequest request) async {
    final capabilities = await getSupportedConversions();
    final isSupported = capabilities.any(
      (conversion) =>
          conversion.source == request.sourceFormat &&
          conversion.target == request.targetFormat,
    );
    if (!isSupported) {
      return const ConversionResult(
        success: false,
        message: 'Bu dönüşüm türü desteklenmiyor.',
        durationMs: 0,
        errorCode: 'unsupported_conversion',
      );
    }

    final process = await _ensureProcess();
    final requestId = _nextRequestId();
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
        'Dönüştürme isteği yerel motora gönderilemedi: $error',
      );
    }

    return completer.future;
  }

  @override
  Future<ConversionPlan> planConversion(ConversionRequest request) async {
    final capabilities = await getSupportedConversions();
    final isSupported = capabilities.any(
      (conversion) =>
          conversion.source == request.sourceFormat &&
          conversion.target == request.targetFormat,
    );
    if (!isSupported) {
      return const ConversionPlan(
        success: false,
        message: 'Bu dönüşüm türü desteklenmiyor.',
        durationMs: 0,
        errorCode: 'unsupported_conversion',
      );
    }

    final process = await _ensureProcess();
    final requestId = _nextRequestId();
    final completer = Completer<ConversionPlan>();
    _pendingPlanRequests[requestId] = completer;
    try {
      await _enqueueMessage(process, {
        'id': requestId,
        'action': 'plan_conversion',
        'source_format': request.sourceFormat.extension,
        'target_format': request.targetFormat.extension,
        'input_path': request.inputPath,
        'output_path': request.outputPath,
        'overwrite': false,
      });
    } on Object catch (error) {
      _pendingPlanRequests.remove(requestId);
      throw ConverterEngineException(
        'Dönüşüm planı yerel motordan alınamadı: $error',
      );
    }
    return completer.future;
  }

  String _nextRequestId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${++_requestSequence}';

  Future<void> _enqueueMessage(Process process, Map<String, Object> message) {
    final write = _writeQueue.then((_) async {
      if (!identical(_process, process)) {
        throw const ConverterEngineException(
          'Yerel motor istek gönderilmeden önce kapandı.',
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
    } on ConverterEngineException {
      rethrow;
    } on ProcessException catch (error) {
      throw ConverterEngineException(
        'Yerel dönüştürme motoru başlatılamadı (${error.message}). '
        'Uygulama paketinin eksiksiz olduğunu kontrol edin.',
      );
    } finally {
      if (identical(_startingProcess, start)) {
        _startingProcess = null;
      }
    }
  }

  Future<Process> _startProcess() async {
    final launch = _resolveWorkerLaunch();
    final process = await _processStarter(
      launch.executable,
      launch.arguments,
      workingDirectory: launch.workingDirectory,
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

  _WorkerLaunchConfiguration _resolveWorkerLaunch() {
    final configuredWorker =
        _configuredWorkerExecutable ??
        Platform.environment['UNIVERSAL_CONVERTER_WORKER'];
    if (configuredWorker != null && configuredWorker.isNotEmpty) {
      return _nativeWorkerConfiguration(configuredWorker);
    }

    final packagedWorker = _packagedWorkerPath();
    if (File(packagedWorker).existsSync()) {
      return _nativeWorkerConfiguration(packagedWorker);
    }

    if (_isRelease) {
      throw ConverterEngineException(
        'Paketlenmiş dönüştürme motoru bulunamadı: $packagedWorker',
      );
    }

    final stagedWorker =
        '$_projectRoot${Platform.pathSeparator}backend'
        '${Platform.pathSeparator}dist${Platform.pathSeparator}debug'
        '${Platform.pathSeparator}${_workerFileName()}';
    if (File(stagedWorker).existsSync()) {
      return _nativeWorkerConfiguration(stagedWorker);
    }

    final python =
        _configuredPythonExecutable ??
        Platform.environment['UNIVERSAL_CONVERTER_PYTHON'] ??
        _discoverPythonExecutable(_projectRoot);
    return _WorkerLaunchConfiguration(
      executable: python,
      arguments: const ['-m', 'backend.worker'],
      workingDirectory: _projectRoot,
    );
  }

  _WorkerLaunchConfiguration _nativeWorkerConfiguration(String executable) {
    final worker = File(executable).absolute;
    if (!worker.existsSync()) {
      throw ConverterEngineException(
        'Dönüştürme motoru dosyası bulunamadı: ${worker.path}',
      );
    }
    return _WorkerLaunchConfiguration(
      executable: worker.path,
      arguments: const [],
      workingDirectory: worker.parent.path,
    );
  }

  static String _packagedWorkerPath() {
    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final workerDirectory = Platform.isMacOS
        ? Directory(
            '${executableDirectory.parent.path}${Platform.pathSeparator}'
            'Resources${Platform.pathSeparator}worker',
          )
        : Directory(
            '${executableDirectory.path}${Platform.pathSeparator}worker',
          );
    return '${workerDirectory.path}${Platform.pathSeparator}${_workerFileName()}';
  }

  static String _workerFileName() {
    return Platform.isWindows
        ? 'universal_converter_worker.exe'
        : 'universal_converter_worker';
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
            'Yerel dönüştürme motoru beklenmeyen şekilde durdu.';
        _failAll(ConverterEngineException(message));
        return;
      }
      if (requestId is! String) {
        throw const FormatException('String request id expected');
      }

      final type = decoded['type'];
      final resultCompleter = _pendingRequests[requestId];
      if (resultCompleter != null) {
        final result = ConversionResult.fromJson(decoded);
        _pendingRequests.remove(requestId);
        resultCompleter.complete(result);
        return;
      }
      final planCompleter = _pendingPlanRequests[requestId];
      if (planCompleter != null) {
        if (type != 'conversion_plan') {
          throw const FormatException('Conversion plan expected');
        }
        final plan = ConversionPlan.fromJson(decoded);
        _pendingPlanRequests.remove(requestId);
        planCompleter.complete(plan);
        return;
      }
      final capabilityCompleter = _pendingCapabilityRequests[requestId];
      if (capabilityCompleter != null) {
        if (type != 'capabilities_result' || decoded['success'] != true) {
          _pendingCapabilityRequests.remove(requestId);
          capabilityCompleter.completeError(
            ConverterEngineException(
              decoded['message'] as String? ??
                  'Desteklenen formatlar alınamadı.',
            ),
          );
          return;
        }
        final rawConversions = decoded['conversions'];
        if (rawConversions is! List) {
          throw const FormatException('Conversions list expected');
        }
        final conversions = [
          for (final item in rawConversions)
            if (item is Map<String, dynamic>)
              SupportedConversion.fromJson(item)
            else
              throw const FormatException('Conversion object expected'),
        ];
        _pendingCapabilityRequests.remove(requestId);
        capabilityCompleter.complete(conversions);
        return;
      }
      developer.log(
        'Bilinmeyen worker yanıt kimliği: $requestId',
        name: 'universal_converter.worker',
      );
    } on Object catch (error, stackTrace) {
      _handleProtocolFailure(error, stackTrace);
    }
  }

  void _handleProtocolStreamError(Object error, StackTrace stackTrace) {
    _handleProtocolFailure(error, stackTrace);
  }

  void _handleProtocolFailure(Object error, StackTrace stackTrace) {
    developer.log(
      'Yerel motordan geçersiz protokol mesajı alındı.',
      name: 'universal_converter.worker',
      error: error,
      stackTrace: stackTrace,
    );
    _failAll(
      const ConverterEngineException(
        'Yerel dönüştürme motorundan geçersiz bir yanıt alındı.',
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
          'Yerel dönüştürme motoru beklenmeyen şekilde kapandı '
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
    final planCompleters = _pendingPlanRequests.values.toList();
    _pendingPlanRequests.clear();
    for (final completer in planCompleters) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    final capabilityCompleters = _pendingCapabilityRequests.values.toList();
    _pendingCapabilityRequests.clear();
    for (final completer in capabilityCompleters) {
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
          'bin${Platform.pathSeparator}python',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return Platform.isWindows ? 'python' : 'python3';
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
      for (var depth = 0; depth < 10; depth++) {
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
