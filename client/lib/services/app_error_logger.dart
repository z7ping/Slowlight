import 'dart:io';

typedef ErrorLogDirectoryProvider = Future<Directory> Function();

class AppErrorLogger {
  AppErrorLogger({
    ErrorLogDirectoryProvider? directoryProvider,
    this.maxBytes = 1024 * 1024,
    DateTime Function()? now,
  })  : _directoryProvider = directoryProvider ?? _defaultDirectory,
        _now = now ?? DateTime.now;

  static final AppErrorLogger instance = AppErrorLogger();
  static const _logFileName = 'slowlight-error.log';
  static const _appDirectoryName = 'Slowlight';

  static String get defaultLogPath {
    final directory = _defaultDirectorySync();
    return '${directory.path}${Platform.pathSeparator}$_logFileName';
  }

  final ErrorLogDirectoryProvider _directoryProvider;
  final DateTime Function() _now;
  final int maxBytes;

  Future<File?> write({
    required String source,
    required Object error,
    StackTrace? stackTrace,
  }) async {
    try {
      final directory = await _directoryProvider();
      await directory.create(recursive: true);
      final separator = Platform.pathSeparator;
      final file = File('${directory.path}$separator$_logFileName');
      await _rotateIfNeeded(file);

      final buffer = StringBuffer()
        ..writeln('${_now().toUtc().toIso8601String()} [$source]')
        ..writeln(error);
      if (stackTrace != null) {
        buffer.writeln(stackTrace);
      }
      buffer.writeln();
      await file.writeAsString(buffer.toString(), mode: FileMode.append, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<String?> get logPath async {
    try {
      final directory = await _directoryProvider();
      return '${directory.path}${Platform.pathSeparator}$_logFileName';
    } catch (_) {
      return null;
    }
  }

  Future<void> _rotateIfNeeded(File file) async {
    if (!await file.exists() || await file.length() < maxBytes) return;

    final backup = File('${file.path}.1');
    if (await backup.exists()) {
      await backup.delete();
    }
    await file.rename(backup.path);
  }

  static Future<Directory> _defaultDirectory() async => _defaultDirectorySync();

  static Directory _defaultDirectorySync() {
    final environment = Platform.environment;
    if (Platform.isWindows) {
      final base = environment['LOCALAPPDATA'];
      if (base != null && base.isNotEmpty) {
        return Directory('$base${Platform.pathSeparator}$_appDirectoryName${Platform.pathSeparator}logs');
      }
    }
    if (Platform.isMacOS) {
      final home = environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory(
          '$home${Platform.pathSeparator}Library${Platform.pathSeparator}'
          'Application Support${Platform.pathSeparator}$_appDirectoryName${Platform.pathSeparator}logs',
        );
      }
    }
    if (Platform.isLinux) {
      final base = environment['XDG_DATA_HOME'];
      if (base != null && base.isNotEmpty) {
        return Directory('$base${Platform.pathSeparator}$_appDirectoryName${Platform.pathSeparator}logs');
      }
      final home = environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory(
          '$home${Platform.pathSeparator}.local${Platform.pathSeparator}share'
          '${Platform.pathSeparator}$_appDirectoryName${Platform.pathSeparator}logs',
        );
      }
    }
    return Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}$_appDirectoryName${Platform.pathSeparator}logs',
    );
  }
}
