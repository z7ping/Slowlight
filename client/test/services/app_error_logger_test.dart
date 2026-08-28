import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/app_error_logger.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('slowlight-error-log-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('creates the log directory and appends error details', () async {
    final logger = AppErrorLogger(
      directoryProvider: () async => Directory('${tempDir.path}/nested/logs'),
      now: () => DateTime.utc(2026, 8, 10, 20, 30),
    );

    final file = await logger.write(
      source: 'FlutterError',
      error: StateError('boom'),
      stackTrace: StackTrace.fromString('line one'),
    );

    expect(file, isNotNull);
    expect(await file!.exists(), isTrue);
    final contents = await file.readAsString();
    expect(contents, contains('2026-08-10T20:30:00.000Z'));
    expect(contents, contains('[FlutterError]'));
    expect(contents, contains('Bad state: boom'));
    expect(contents, contains('line one'));
  });

  test('rotates one backup before appending when the size limit is reached', () async {
    final logsDir = Directory('${tempDir.path}/logs');
    await logsDir.create(recursive: true);
    final current = File('${logsDir.path}/slowlight-error.log');
    await current.writeAsString('12345678');
    final logger = AppErrorLogger(
      directoryProvider: () async => logsDir,
      maxBytes: 8,
    );

    await logger.write(source: 'async', error: 'new error');

    final backup = File('${logsDir.path}/slowlight-error.log.1');
    expect(await backup.readAsString(), '12345678');
    expect(await current.readAsString(), contains('new error'));
  });

  test('does not throw when the log directory cannot be resolved', () async {
    final logger = AppErrorLogger(
      directoryProvider: () async => throw const FileSystemException('denied'),
    );

    final result = await logger.write(source: 'async', error: 'boom');

    expect(result, isNull);
  });
}
