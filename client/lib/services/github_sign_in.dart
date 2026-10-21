import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'auth_service.dart';
import 'network_retry.dart';

/// OAuth 回调唤醒 Android 后，立即检查授权结果，而不是等下一轮定时轮询。
class _OAuthResumeObserver extends WidgetsBindingObserver {
  Completer<void>? _resume;
  bool _wakeRequested = false;

  void wakeUp() {
    final signal = _resume;
    if (signal != null && !signal.isCompleted) {
      signal.complete();
    } else {
      _wakeRequested = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) wakeUp();
  }

  Future<void> waitUntilPoll() async {
    if (_wakeRequested) {
      _wakeRequested = false;
      return;
    }
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
  static _OAuthResumeObserver? _activeObserver;

  /// 桌面端在浏览器授权后可以主动唤醒正在等待的 OAuth 轮询。
  /// 只检查已有授权会话；不会重新申请授权或重复领取凭据。
  static bool checkAuthorizationNow() {
    final observer = _activeObserver;
    if (observer == null) return false;
    observer.wakeUp();
    return true;
  }

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

  /// Android 从浏览器返回时可能短暂无法解析域名。
  /// 只允许重试确认未送达的请求；轮询成功会消费一次性凭据。
  @visibleForTesting
  static bool isTransientNetworkFailure(Object error) =>
      NetworkRetry.isNetworkFailure(error);

  @visibleForTesting
  static bool isSafeToRetryPoll(Object error) =>
      NetworkRetry.requestNotSent(error);

  static String describeError(Object error) {
    if (!isTransientNetworkFailure(error)) return error.toString();
    final host = Uri.parse(ApiService.baseUrl).host;
    return '无法连接云端服务（$host）。请检查网络、DNS 或服务地址后重试。';
  }

  @visibleForTesting
  static Future<Map<String, dynamic>?> pollWithNetworkRetry({
    required Future<Map<String, dynamic>> Function() request,
    required bool Function() shouldContinue,
    Future<void> Function(Duration)? delay,
    double Function()? randomUnit,
  }) =>
      NetworkRetry.run<Map<String, dynamic>>(
        request: request,
        canRetry: isSafeToRetryPoll,
        shouldContinue: shouldContinue,
        delay: delay,
        randomUnit: randomUnit,
      );

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
    _activeObserver = resumeObserver;
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
          await AuthService.completeOAuthLogin(
            result,
            linkingExisting: linkExisting,
          );
          return true;
        }
        throw StateError('GitHub 登录状态异常，请重试');
      }
      throw StateError('GitHub 授权已超时，请重新发起登录');
    } finally {
      WidgetsBinding.instance.removeObserver(resumeObserver);
      if (identical(_activeObserver, resumeObserver)) {
        _activeObserver = null;
      }
    }
  }
}
