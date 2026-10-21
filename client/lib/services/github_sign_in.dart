import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'auth_service.dart';

/// OAuth 回调唤醒 Android 后，立即检查授权结果，而不是等下一轮定时轮询。
class _OAuthResumeObserver extends WidgetsBindingObserver {
  Completer<void>? _resume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final signal = _resume;
      if (signal != null && !signal.isCompleted) signal.complete();
    }
  }

  Future<void> waitUntilPoll() async {
    final signal = Completer<void>();
    _resume = signal;
    try {
      await Future.any<void>([
        Future<void>.delayed(const Duration(seconds: 3)),
        signal.future,
      ]);
    } finally {
      if (identical(_resume, signal)) _resume = null;
    }
  }
}

/// Android 优先使用系统安全浏览器标签（Custom Tabs），沿用浏览器登录态。
/// GitHub 未承诺第三方 OAuth 可交由 GitHub App 接管，不能拼造 App scheme。
/// Windows 仍通过默认浏览器授权；两端都通过服务端一次性凭据领取 JWT。
class GitHubSignIn {
  @visibleForTesting
  static Future<bool> openAuthorization(
    Uri authUrl, {
    TargetPlatform? platform,
    Future<bool> Function(LaunchMode)? supportsMode,
    Future<bool> Function(Uri, LaunchMode)? launch,
  }) async {
    final target = platform ?? defaultTargetPlatform;
    final tryLaunch = launch ??
        (Uri url, LaunchMode mode) => launchUrl(url, mode: mode);
    if (!kIsWeb && target == TargetPlatform.android) {
      // Android 11+ 的 Custom Tabs 查询能力由 AndroidManifest <queries> 授权。
      bool supportsTabs = false;
      try {
        supportsTabs = await (supportsMode ?? supportsLaunchMode)(
          LaunchMode.inAppBrowserView,
        );
      } catch (_) {
        // 未安装可用浏览器标签组件时仍可退回系统默认浏览器。
      }
      if (supportsTabs) {
        try {
          if (await tryLaunch(authUrl, LaunchMode.inAppBrowserView)) {
            return true;
          }
        } catch (_) {
          // 浏览器标签启动失败时回退普通浏览器，不中断授权。
        }
      }
    }
    return tryLaunch(authUrl, LaunchMode.externalApplication);
  }

  /// Android 从浏览器恢复时，系统网络和 DNS 可能尚未就绪。
  /// 只重试传输层故障，不能重试授权拒绝、会话过期等服务端错误。
  @visibleForTesting
  static bool isTransientNetworkFailure(Object error) {
    if (error is TimeoutException || error is http.ClientException) {
      return true;
    }
    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('connection reset') ||
        message.contains('connection refused');
  }

  /// poll 是一次性领取 JWT 的 POST，超时/断链可能已被服务端消费。
  /// 仅 DNS 失败等确认请求未送达的错误允许重试。
  @visibleForTesting
  static bool isSafeToRetryPoll(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('connection refused') ||
        message.contains('no route to host');
  }

  static String describeError(Object error) {
    if (!isTransientNetworkFailure(error)) return error.toString();
    final host = Uri.parse(ApiService.baseUrl).host;
    return '无法连接云端服务（$host），请检查网络和 DNS 解析，'
        '或确认服务器域名配置后重试。';
  }

  @visibleForTesting
  static Future<Map<String, dynamic>?> pollWithNetworkRetry({
    required Future<Map<String, dynamic>> Function() request,
    required bool Function() shouldContinue,
    Future<void> Function(Duration)? delay,
  }) async {
    for (var attempt = 1; attempt <= 4; attempt++) {
      if (!shouldContinue()) return null;
      try {
        return await request();
      } catch (error) {
        if (!isSafeToRetryPoll(error) || attempt == 4) rethrow;
        const pause = Duration(seconds: 2);
        await (delay?.call(pause) ?? Future<void>.delayed(pause));
      }
    }
    return null;
  }

  static Future<bool> signIn({
    required bool Function() shouldContinue,
    bool linkExisting = false,
  }) async {
    ApiService.validateCloudEndpoint();
    final endpoint = Uri.parse(ApiService.baseUrl);
    if (endpoint.scheme != 'https' &&
        endpoint.host != 'localhost' &&
        endpoint.host != '127.0.0.1') {
      throw StateError('GitHub 登录要求 HTTPS 云端服务');
    }

    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final start = await ApiService.post(
      linkExisting ? '/auth/github/link/start' : '/auth/github/start',
      body: {'platform': isAndroid ? 'android' : 'desktop'},
      authenticated: linkExisting,
    );
    if (!shouldContinue()) return false;
    final authUrl = Uri.parse(start['authorization_url'] as String);
    final sessionId = start['session_id'] as String;
    final pollToken = start['poll_token'] as String;
    if (authUrl.scheme != 'https' || authUrl.host != 'github.com') {
      throw StateError('GitHub 授权地址无效');
    }

    final resumeObserver = _OAuthResumeObserver();
    WidgetsBinding.instance.addObserver(resumeObserver);
    try {
      if (!await openAuthorization(authUrl)) {
        throw StateError('无法打开 GitHub 授权页面，请检查系统默认浏览器');
      }
      // Android 回调只负责唤醒 App，JWT 仍通过 poll_token 从服务端领取。
      final expires = start['expires_in'];
      final deadline = DateTime.now().add(
        Duration(seconds: expires is int ? expires : 600),
      );
      while (DateTime.now().isBefore(deadline)) {
        if (!shouldContinue()) return false;
        await resumeObserver.waitUntilPoll();
        if (!shouldContinue()) return false;

        final result = await pollWithNetworkRetry(
          request: () => ApiService.post('/auth/github/poll', body: {
            'session_id': sessionId,
            'poll_token': pollToken,
          }),
          shouldContinue: shouldContinue,
        );
        if (!shouldContinue() || result == null) return false;
        if (result['status'] == 'pending') continue;
        if (result['status'] == 'complete') {
          await AuthService.completeOAuthLogin(result);
          return true;
        }
        throw StateError('GitHub 登录状态异常，请重试');
      }
      throw StateError('GitHub 授权已超时，请重新发起登录');
    } finally {
      WidgetsBinding.instance.removeObserver(resumeObserver);
    }
  }
}
