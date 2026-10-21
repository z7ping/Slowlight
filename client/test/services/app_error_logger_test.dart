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

  test('readText combines rotated backup and current entries', () async {
    final logger = AppErrorLogger(
      directoryProvider: () async => tempDir,
      maxBytes: 8,
    );
    await logger.write(source: 'network', error: 'first');
    await logger.write(source: 'network', error: 'second');
    final text = await logger.readText();
    expect(text, contains('first'));
    expect(text, contains('second'));
    await logger.clear();
    expect(await logger.readText(), isEmpty);
  });

  test('concurrent error writes are serialized', () async {
    final logger = AppErrorLogger(directoryProvider: () async => tempDir);
    await Future.wait(
      List.generate(15, (i) => logger.write(
        source: 'concurrent',
        error: 'error-$i',
      )),
    );
    final text = await logger.readText();
    for (var i = 0; i < 15; i++) {
      expect(text, contains('error-$i'));
    }
  });

  test('redacts credential values and JWTs from exported records', () async {
    final logger = AppErrorLogger(directoryProvider: () async => tempDir);
    const secret = 'example123456';
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature';
    await logger.write(
      source: 'auth',
      error: 'Bearer $secret password=$secret poll_token=$secret $jwt',
    );
    final text = await logger.readText();
    expect(text, isNot(contains(secret)));
    expect(text, isNot(contains(jwt)));
    expect(text, contains('[REDACTED]'));
  });

  test('recent log preview is bounded but source file remains intact', () async {
    final logger = AppErrorLogger(directoryProvider: () async => tempDir);
    await logger.write(source: 'network', error: '1234567890');
    final recent = await logger.readRecent(maxCharacters: 8);
    expect(recent, contains('仅展示末尾内容'));
    expect(await logger.readText(), contains('1234567890'));
  });

}
