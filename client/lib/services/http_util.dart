import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// HTTP 请求工具类。
///
/// 只记录方法、URL、状态码和耗时；请求体、响应体与认证头都可能包含密码、
/// Token、迁移快照或第三方凭据，禁止写入日志。
class HttpUtil {
  /// GET 请求
  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    _logRequest('GET', url);
    final sw = Stopwatch()..start();
    try {
      final response = await http.get(url, headers: headers).timeout(
        timeout ?? const Duration(seconds: 8),
      );
      sw.stop();
      _logResponse('GET', url, response.statusCode, sw.elapsedMilliseconds);
      return response;
    } catch (e) {
      sw.stop();
      _logError('GET', url, sw.elapsedMilliseconds, e);
      rethrow;
    }
  }

  /// POST 请求
  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    _logRequest('POST', url);
    final sw = Stopwatch()..start();
    try {
      final response = await http.post(url, headers: headers, body: body).timeout(
        timeout ?? const Duration(seconds: 15),
      );
      sw.stop();
      _logResponse('POST', url, response.statusCode, sw.elapsedMilliseconds);
      return response;
    } catch (e) {
      sw.stop();
      _logError('POST', url, sw.elapsedMilliseconds, e);
      rethrow;
    }
  }

  /// PUT 请求
  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    _logRequest('PUT', url);
    final sw = Stopwatch()..start();
    try {
      final response = await http.put(url, headers: headers, body: body).timeout(
        timeout ?? const Duration(seconds: 15),
      );
      sw.stop();
      _logResponse('PUT', url, response.statusCode, sw.elapsedMilliseconds);
      return response;
    } catch (e) {
      sw.stop();
      _logError('PUT', url, sw.elapsedMilliseconds, e);
      rethrow;
    }
  }

  /// DELETE 请求
  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    _logRequest('DELETE', url);
    final sw = Stopwatch()..start();
    try {
      final response = await http.delete(url, headers: headers, body: body).timeout(
        timeout ?? const Duration(seconds: 15),
      );
      sw.stop();
      _logResponse('DELETE', url, response.statusCode, sw.elapsedMilliseconds);
      return response;
    } catch (e) {
      sw.stop();
      _logError('DELETE', url, sw.elapsedMilliseconds, e);
      rethrow;
    }
  }

  /// PATCH 请求
  static Future<http.Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    _logRequest('PATCH', url);
    final sw = Stopwatch()..start();
    try {
      final response = await http.patch(url, headers: headers, body: body).timeout(
        timeout ?? const Duration(seconds: 15),
      );
      sw.stop();
      _logResponse('PATCH', url, response.statusCode, sw.elapsedMilliseconds);
      return response;
    } catch (e) {
      sw.stop();
      _logError('PATCH', url, sw.elapsedMilliseconds, e);
      rethrow;
    }
  }

  static void _logRequest(String method, Uri url) {
    if (!kDebugMode) return;
    debugPrint('[HTTP] → $method $url');
  }

  static void _logResponse(
    String method,
    Uri url,
    int statusCode,
    int ms,
  ) {
    if (!kDebugMode) return;
    debugPrint('[HTTP] ← $method $url | $statusCode | ${ms}ms');
  }

  static void _logError(String method, Uri url, int ms, Object error) {
    if (!kDebugMode) return;
    debugPrint('[HTTP] ✖ $method $url | ${ms}ms | ${error.runtimeType}');
  }
}
