import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_error_logger.dart';

/// Only the three existing credential-related keys are traced.
/// Never record a secret, key content, request body, account identity or hash.
enum AuthStorageSlot {
  access('auth_token'),
  refresh('auth_refresh_token'),
  oauthPending('github_oauth_pending');

  const AuthStorageSlot(this.key);
  final String key;
}

/// Process-local operation sequence correlates overlapping secure-storage
/// reads/writes/deletes without storing a credential or making network calls.
class AuthStorageDiagnostics {
  AuthStorageDiagnostics._();

  static int _sequence = 0;
  static bool _started = false;

  @visibleForTesting
  static void Function(String)? debugTraceSink;

  static void _record(String event) {
    if (!_started) {
      _started = true;
      _recordEvent('process_started trace=auth_storage_v1');
    }
    _recordEvent(event);
  }

  static void _recordEvent(String event) {
    final line = 'seq=${++_sequence} $event';
    try {
      debugTraceSink?.call(line);
    } catch (_) {
      // A diagnostic listener must not affect authentication.
    }
    unawaited(AppErrorLogger.instance.write(
      source: 'AuthStorage',
      error: line,
    ));
  }

  static Future<String?> read(
    FlutterSecureStorage storage, {
    required AuthStorageSlot slot,
    required String actor,
    bool logPresent = false,
  }) async {
    final operation = ++_sequence;
    try {
      final value = await storage.read(key: slot.key);
      if (logPresent || value == null || value.isEmpty) {
        final status = value == null
            ? 'missing'
            : value.isEmpty
                ? 'empty'
                : 'present';
        _recordEvent(
          'op=$operation action=read slot=${slot.name} actor=$actor status=$status',
        );
      }
      return value;
    } catch (error) {
      _recordEvent(
        'op=$operation action=read slot=${slot.name} actor=$actor '
        'status=error kind=${error.runtimeType}',
      );
      rethrow;
    }
  }

  static Future<void> write(
    FlutterSecureStorage storage, {
    required AuthStorageSlot slot,
    required String value,
    required String actor,
  }) async {
    final operation = ++_sequence;
    _record('op=$operation action=write slot=${slot.name} actor=$actor phase=start');
    try {
      await storage.write(key: slot.key, value: value);
      _recordEvent(
        'op=$operation action=write slot=${slot.name} actor=$actor phase=done',
      );
    } catch (error) {
      _recordEvent(
        'op=$operation action=write slot=${slot.name} actor=$actor '
        'phase=failed kind=${error.runtimeType}',
      );
      rethrow;
    }
  }

  static Future<void> delete(
    FlutterSecureStorage storage, {
    required AuthStorageSlot slot,
    required String actor,
  }) async {
    final operation = ++_sequence;
    _record('op=$operation action=delete slot=${slot.name} actor=$actor phase=start');
    try {
      await storage.delete(key: slot.key);
      _recordEvent(
        'op=$operation action=delete slot=${slot.name} actor=$actor phase=done',
      );
    } catch (error) {
      _recordEvent(
        'op=$operation action=delete slot=${slot.name} actor=$actor '
        'phase=failed kind=${error.runtimeType}',
      );
      rethrow;
    }
  }

  /// Best-effort presence probe, never used to decide whether to log in.
  /// It is reserved for the rare OAuth pending-key cleanup boundary.
  static Future<void> checkpoint(
    FlutterSecureStorage storage, {
    required AuthStorageSlot slot,
    required String actor,
  }) async {
    try {
      await read(storage, slot: slot, actor: actor, logPresent: true);
    } catch (_) {
      // Diagnostics must not block the actual pending-state cleanup.
    }
  }
}
