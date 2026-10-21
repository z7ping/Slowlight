import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slowlight/services/github_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  const url = 'https://github.com/login/oauth/authorize?client_id=test';

  test('Android 支持 Custom Tabs 时优先走安全浏览器授权', () async {
    final launched = <LaunchMode>[];
    final success = await GitHubSignIn.openAuthorization(
      Uri.parse(url),
      platform: TargetPlatform.android,
      supportsMode: (mode) async => mode == LaunchMode.inAppBrowserView,
      launch: (uri, mode) async {
        expect(uri.toString(), url);
        launched.add(mode);
        return true;
      },
    );
    expect(success, isTrue);
    expect(launched, [LaunchMode.inAppBrowserView]);
  });

  test('Android 不支持 Custom Tabs 时退回默认浏览器', () async {
    final launched = <LaunchMode>[];
    final success = await GitHubSignIn.openAuthorization(
      Uri.parse(url),
      platform: TargetPlatform.android,
      supportsMode: (_) async => false,
      launch: (_, mode) async {
        launched.add(mode);
        return true;
      },
    );
    expect(success, isTrue);
    expect(launched, [LaunchMode.externalApplication]);
  });

  test('Android Custom Tabs 启动异常时不会阻断 OAuth', () async {
    final launched = <LaunchMode>[];
    final success = await GitHubSignIn.openAuthorization(
      Uri.parse(url),
      platform: TargetPlatform.android,
      supportsMode: (_) async => true,
      launch: (_, mode) async {
        launched.add(mode);
        if (mode == LaunchMode.inAppBrowserView) {
          throw StateError('Custom Tabs unavailable');
        }
        return true;
      },
    );
    expect(success, isTrue);
    expect(launched, [
      LaunchMode.inAppBrowserView,
      LaunchMode.externalApplication,
    ]);
  });

  test('Windows 不存在待核验会话时不误报授权已检查', () {
    expect(GitHubSignIn.checkAuthorizationNow(), isFalse);
  });

  test('Windows 不使用 Android 回跳方式，始终使用默认浏览器', () async {
    final launched = <LaunchMode>[];
    final success = await GitHubSignIn.openAuthorization(
      Uri.parse(url),
      platform: TargetPlatform.windows,
      supportsMode: (_) async {
        fail('Windows 不应检测 Android Custom Tabs');
      },
      launch: (_, mode) async {
        launched.add(mode);
        return true;
      },
    );
    expect(success, isTrue);
    expect(launched, [LaunchMode.externalApplication]);
  });

  test('GitHub 轮询对确认未送达的请求重试，恢复后继续授权', () async {
    var attempts = 0;
    final pauses = <Duration>[];
    final result = await GitHubSignIn.pollWithNetworkRetry(
      request: () async {
        attempts++;
        if (attempts == 1) {
          throw http.ClientException(
            'ClientException with SocketException: Failed host lookup',
          );
        }
        return {'status': 'complete'};
      },
      shouldContinue: () => true,
      delay: (duration) async {
        pauses.add(duration);
      },
      randomUnit: () => 0.5,
    );
    expect(result?['status'], 'complete');
    expect(attempts, 2);
    expect(pauses, [const Duration(seconds: 1)]);
  });

  test('GitHub 轮询临时故障最多尝试四次，并提供友好错误信息', () async {
    var attempts = 0;
    await expectLater(
      GitHubSignIn.pollWithNetworkRetry(
        request: () async {
          attempts++;
          throw http.ClientException('Failed host lookup: example.invalid');
        },
        shouldContinue: () => true,
        delay: (_) async {},
      ),
      throwsA(isA<http.ClientException>()),
    );
    expect(attempts, 4);
    expect(
      GitHubSignIn.describeError(http.ClientException('Failed host lookup')),
      contains('DNS'),
    );
  });

  test('GitHub 轮询不重试服务端认证错误，也不会吞掉异常', () async {
    var attempts = 0;
    await expectLater(
      GitHubSignIn.pollWithNetworkRetry(
        request: () async {
          attempts++;
          throw StateError('授权会话已过期');
        },
        shouldContinue: () => true,
        delay: (_) async {},
      ),
      throwsA(isA<StateError>()),
    );
    expect(attempts, 1);
  });

  test('GitHub 轮询网络重试时取消，不继续请求', () async {
    var attempts = 0;
    var active = true;
    final result = await GitHubSignIn.pollWithNetworkRetry(
      request: () async {
        attempts++;
        throw http.ClientException('Failed host lookup');
      },
      shouldContinue: () => active,
      delay: (_) async {
        active = false;
      },
    );
    expect(result, isNull);
    expect(attempts, 1);
  });

  test('GitHub 轮询连接重置不重试，避免重复领取一次性凭据', () async {
    var attempts = 0;
    await expectLater(
      GitHubSignIn.pollWithNetworkRetry(
        request: () async {
          attempts++;
          throw http.ClientException('Connection reset by peer');
        },
        shouldContinue: () => true,
        delay: (_) async {},
      ),
      throwsA(isA<http.ClientException>()),
    );
    expect(attempts, 1);
  });

  test('GitHub 轮询按 1、2、4 秒指数退避且最多四次', () async {
    var attempts = 0;
    final pauses = <Duration>[];
    final result = await GitHubSignIn.pollWithNetworkRetry(
      request: () async {
        attempts++;
        if (attempts <= 3) {
          throw http.ClientException('Failed host lookup: example.invalid');
        }
        return {'status': 'complete'};
      },
      shouldContinue: () => true,
      delay: (duration) async {
        pauses.add(duration);
      },
      randomUnit: () => 0.5,
    );
    expect(attempts, 4);
    expect(result?['status'], 'complete');
    expect(pauses, [
      const Duration(seconds: 1),
      const Duration(seconds: 2),
      const Duration(seconds: 4),
    ]);
  });

}
