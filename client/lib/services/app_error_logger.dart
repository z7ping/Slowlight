import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef ErrorLogDirectoryProvider = Future<Directory> Function();

/// 应用私有日志：最大 1MB + 单份轮转备份；默认不上传。
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
    if (Platform.isAndroid || Platform.isIOS) return '设置 → 应用诊断';
    final directory = _defaultDirectorySync();
    return '${directory.path}${Platform.pathSeparator}$_logFileName';
  }

  final ErrorLogDirectoryProvider _directoryProvider;
  final DateTime Function() _now;
  final int maxBytes;
  Future<void> _pendingWrite = Future<void>.value();

  /// 串行化日志写入，避免多个异步异常同时写入造成轮转/文件损坏。
  Future<File?> write({
    required String source,
    required Object error,
    StackTrace? stackTrace,
  }) {
    final operation = _pendingWrite.then((_) async {
      try {
        final directory = await _directoryProvider();
        await directory.create(recursive: true);
        final file =
            File('${directory.path}${Platform.pathSeparator}$_logFileName');
        await _rotateIfNeeded(file);
        final entry = StringBuffer()
          ..writeln('${_now().toUtc().toIso8601String()} [${_redact(source)}]')
          ..writeln(_redact(error.toString()));
        if (stackTrace != null) entry.writeln(_redact(stackTrace.toString()));
        entry.writeln();
        await file.writeAsString(entry.toString(),
            mode: FileMode.append, flush: true);
        return file;
      } catch (_) {
        return null;
      }
    });
    _pendingWrite = operation.then((_) {});
    return operation;
  }

  static String _redact(String input) {
    var sanitized = input.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    // 常见凭据键值/URL 参数与 JWT；不保留敏感授权信息。
    sanitized = sanitized.replaceAllMapped(
      RegExp(
          r'''\b(password|access_token|refresh_token|poll_token|api_key|client_secret|authorization|code_verifier|session_id|code|jwt|token)(\s*["']?\s*[:=]\s*["']?)([^\s&,"'}]+)''',
          caseSensitive: false),
      (match) => '${match[1]}${match[2]}[REDACTED]',
    );
    // OAuth state 只匹配参数或带引号的键，避免误伤 “Bad state: ...”。
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'''((?:\bstate\s*=|["']state["']\s*:)\s*["']?)([^\s&,"'}]+)''',
          caseSensitive: false),
      (match) => '${match[1]}[REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
      '[REDACTED_JWT]',
    );
    return sanitized;
  }

  Future<String> readText() async {
    await _pendingWrite;
    final directory = await _directoryProvider();
    final base = '${directory.path}${Platform.pathSeparator}$_logFileName';
    final result = StringBuffer();
    for (final path in ['$base.1', base]) {
      final file = File(path);
      if (await file.exists()) {
        result.write(await file.readAsString());
      }
    }
    return result.toString();
  }

  Future<String> readRecent({int maxCharacters = 24000}) async {
    final text = await readText();
    if (text.length <= maxCharacters) return text;
    return '（仅展示末尾内容，导出包含完整日志）\n\n'
        '${text.substring(text.length - maxCharacters)}';
  }

  Future<void> clear() async {
    await _pendingWrite;
    final directory = await _directoryProvider();
    final base = '${directory.path}${Platform.pathSeparator}$_logFileName';
    for (final path in [base, '$base.1']) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  /// 在缓存目录创建供 Android FileProvider 分享的脱敏文本副本。
  Future<File> createExportFile({String header = ''}) async {
    final text = await readText();
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}diagnostics',
    );
    await directory.create(recursive: true);
    final export = File(
      '${directory.path}${Platform.pathSeparator}slowlight-diagnostics.txt',
    );
    await export.writeAsString('$header\n$text', flush: true);
    return export;
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
    if (await backup.exists()) await backup.delete();
    await file.rename(backup.path);
  }

  static Future<Directory> _defaultDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final root = await getApplicationSupportDirectory();
      return Directory('${root.path}${Platform.pathSeparator}logs');
    }
    return _defaultDirectorySync();
  }

  static Directory _defaultDirectorySync() {
    final environment = Platform.environment;
    if (Platform.isWindows) {
      final base = environment['LOCALAPPDATA'];
      if (base != null && base.isNotEmpty) {
        return Directory(
            '$base${Platform.pathSeparator}$_appDirectoryName${Platform.pathSeparator}logs');
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
        return Directory(
            '$base${Platform.pathSeparator}$_appDirectoryName${Platform.pathSeparator}logs');
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
