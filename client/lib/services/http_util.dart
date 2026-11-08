import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_error_logger.dart';
import 'auth_service.dart';

/// HTTP 请求工具类。日志只包含请求方法、URL 路径、状态码及耗时；
/// 禁止持久化 Authorization、Refresh Token、请求/响应体。
class HttpUtil {
  static Future<http.Response> get(Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) => _perform('GET', url, headers: headers, timeout: timeout);

  static Future<http.Response> post(Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) => _perform('POST', url, headers: headers, body: body, timeout: timeout);

  static Future<http.Response> put(Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) => _perform('PUT', url, headers: headers, body: body, timeout: timeout);

  static Future<http.Response> delete(Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) => _perform('DELETE', url, headers: headers, body: body, timeout: timeout);

  static Future<http.Response> patch(Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) => _perform('PATCH', url, headers: headers, body: body, timeout: timeout);

  static Future<http.Response> _perform(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    _logRequest(method, url);
    final sw = Stopwatch()..start();
    final limit = timeout ??
        Duration(seconds: method == 'GET' ? 8 : 15);

    Future<http.Response> send(Map<String, String>? authHeaders) {
      final request = switch (method) {
        'GET' => http.get(url, headers: authHeaders),
        'POST' => http.post(url, headers: authHeaders, body: body),
        'PUT' => http.put(url, headers: authHeaders, body: body),
        'DELETE' => http.delete(url, headers: authHeaders, body: body),
        'PATCH' => http.patch(url, headers: authHeaders, body: body),
        _ => throw StateError('不支持的 HTTP method'),
      };
      return request.timeout(limit);
    }

    try {
      var response = await send(headers);
      if (response.statusCode == 401 && headers != null) {
        // The original 401 can disappear behind a successful retry.
        // Only known auth routes are recorded; never include query, host,
        // Authorization headers or response bodies.
        final endpoint = switch (url.path) {
          '/api/auth/profile' => 'profile',
          '/api/auth/providers' => 'providers',
          '/api/auth/password/status' => 'password_status',
          '/api/auth/refresh' => 'refresh',
          _ => null,
        };
        final authorization = headers['Authorization'] ?? headers['authorization'];
        final bearer = authorization == null || authorization.isEmpty
            ? 'absent'
            : authorization.startsWith('Bearer ') && authorization.length > 7
                ? 'present'
                : 'other';
        if (endpoint != null) {
          // Whether a Bearer existed distinguishes missing local credentials
          // from a server-rejected JWT. Never persist its actual value.
          AppErrorLogger.instance.write(
            source: 'AuthHttp',
            error: 'unauthorized endpoint=$endpoint method=$method '
                'bearer=$bearer',
          );
        }
        if (bearer == 'present') {
          // 401 中间件拒绝后才重试；仅重试当前账号 JWT，
          // OAuth 候选 JWT 不可套用另一个账号的身份。
          String? recovered;
          try {
            recovered = await AuthService.recoverUnauthorized(
                authorization.substring(7));
          } catch (_) {
            // 恢复失败仍返回原始 401，不冒充成功或清除本机凭据。
          }
          if (recovered != null && recovered != authorization.substring(7)) {
            response = await send({
              ...headers, 'Authorization': 'Bearer $recovered',
            });
          }
        }
      }
      sw.stop();
      _logResponse(method, url, response.statusCode, sw.elapsedMilliseconds);
      _recordHttpStatus(method, url, response.statusCode);
      return response;
    } catch (error) {
      sw.stop();
      _logError(method, url, sw.elapsedMilliseconds, error);
      rethrow;
    }
  }

  static void _logRequest(String method, Uri url) {
    if (!kDebugMode) return;
    debugPrint('[HTTP] → $method ${url.path}');
  }

  static void _logResponse(
    String method,
    Uri url,
    int statusCode,
    int ms,
  ) {
    if (!kDebugMode) return;
    debugPrint('[HTTP] ← $method ${url.path} | $statusCode | ${ms}ms');
  }

  static void _logError(String method, Uri url, int ms, Object error) {
    if (kDebugMode) {
      debugPrint('[HTTP] ✖ $method ${url.path} | ${ms}ms | ${error.runtimeType}');
    }
    // 只存方法、路径、异常类型与错误类别；禁止写入 URL 查询、响应体或凭据。
    final kind = error.toString().toLowerCase();
    final category = kind.contains('failed host lookup')
        ? 'DNS 解析失败'
        : kind.contains('timeout') ? '连接超时'
        : kind.contains('connection refused') ? '连接被拒绝'
        : kind.contains('socketexception') ? '网络连接异常' : '请求失败';
    _recordError('$method ${url.path}', '${error.runtimeType}: $category');
  }

  static void _recordHttpStatus(String method, Uri url, int statusCode) {
    if (statusCode < 400) return;
    _recordError('$method ${url.path}', 'HTTP $statusCode');
  }

  static void _recordError(String operation, String summary) {
    if (kIsWeb) return;
    AppErrorLogger.instance.write(
      source: 'HTTP $operation',
      error: summary,
    );
  }
}
