import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
