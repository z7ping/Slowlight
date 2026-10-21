import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/services/auth_service.dart';
import 'package:slowlight/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('正式云端地址只接受 HTTPS，开发/自托管可用本地 HTTP', () {
    expect(
      () => ApiService.validateCloudEndpoint(
        url: 'http://example.org/api', requireHttps: true,
      ),
      throwsStateError,
    );
    expect(
      () => ApiService.validateCloudEndpoint(
        url: 'https://example.org/api', requireHttps: true,
      ),
      returnsNormally,
    );
    expect(
      () => ApiService.validateCloudEndpoint(
        url: 'http://localhost:8080/api', requireHttps: false,
      ),
      returnsNormally,
    );
  });

  test('Cloud auth rejects local token', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'local:123'});
    expect(await AuthService.isLoggedIn(), isFalse);
  });

  test('Cloud auth rejects expired JWT', () async {
    final token = _jwt(exp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - 60);
    SharedPreferences.setMockInitialValues({'auth_token': token});
    expect(await AuthService.isLoggedIn(), isFalse);
  });

  test('Cloud auth accepts unexpired JWT', () async {
    final token = _jwt(exp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600);
    SharedPreferences.setMockInitialValues({'auth_token': token});
    expect(await AuthService.isLoggedIn(), isTrue);
  });

  test('GitHub 登录方式独立于 GitHub 绑定，并在退出后清除', () async {
    final result = <String, dynamic>{
      'token': _jwt(
        exp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600,
      ),
      'user': <String, dynamic>{
        'id': 12,
        'username': 'github_12',
        'nickname': '测试用户',
        'email': '',
        'created_at': '2026-10-21T00:00:00Z',
      },
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_login_method', 'password');

    await AuthService.completeOAuthLogin(result, linkingExisting: true);
    expect(await AuthService.getLastLoginMethod(), 'password');

    await AuthService.completeOAuthLogin(result);
    expect(await AuthService.getLastLoginMethod(), 'github');
    expect((await AuthService.getUser())?.nickname, '测试用户');

    await AuthService.logout();
    expect(await AuthService.getLastLoginMethod(), isNull);
  });

  test('Legacy token is migrated out of SharedPreferences', () async {
    final token = _jwt(exp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600);
    SharedPreferences.setMockInitialValues({'auth_token': token});

    expect(await AuthService.getToken(), token);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_token'), isNull);
    expect(await const FlutterSecureStorage().read(key: 'auth_token'), token);
  });
}

String _jwt({required int exp}) {
  String part(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'exp': exp})}.signature';
}
