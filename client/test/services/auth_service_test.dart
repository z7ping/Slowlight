import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  tearDown(() => AuthService.debugAuthTraceSink = null);

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

  test('credential diagnostics record state transitions once without JWT values', () async {
    final events = <String>[];
    AuthService.debugAuthTraceSink = events.add;
    final token = _jwt(
      exp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600,
    );
    FlutterSecureStorage.setMockInitialValues({'auth_token': token});
    expect(await AuthService.getToken(), token);
    FlutterSecureStorage.setMockInitialValues({});
    expect(await AuthService.getToken(), isNull);
    expect(await AuthService.getToken(), isNull);
    expect(
      events.where((e) => e == 'credential.read origin=none status=missing'),
      hasLength(1),
    );
    expect(
      events.where(
        (e) => e == 'credential.disappeared previous=valid origin=none',
      ),
      hasLength(1),
    );
    expect(events.join('\n'), isNot(contains(token)));
    expect(events.join('\n'), isNot(contains('Bearer ')));
  });

  test('OAuth login records safe save event and no secret material', () async {
    final events = <String>[];
    AuthService.debugAuthTraceSink = events.add;
    final token = _jwt(
      exp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600,
    );
    final response = {
      'token': token,
      'refresh_token': 'test-refresh-credential',
      'user': {
        'id': 40, 'username': 'github_40', 'nickname': '观察用例',
        'email': '', 'created_at': '2026-10-21T00:00:00Z',
      },
    };
    await http.runWithClient(
      () => AuthService.completeOAuthLogin(response),
      () => MockClient((request) async {
        expect(request.url.path, '/api/auth/profile');
        return http.Response(jsonEncode(response['user']), 200);
      }),
    );
    expect(events, contains(
      'credential.save_completed method=github refresh=present',
    ));
    final recorded = events.join('\n');
    expect(recorded, isNot(contains(token)));
    expect(recorded, isNot(contains('test-refresh-credential')));
    expect(recorded, isNot(contains('github_40')));
    expect(await AuthService.getToken(), token);

    // Android diagnostics captured exactly this transition after GitHub
    // sign-in: a verified, saved JWT vanished without a logout event.
    FlutterSecureStorage.setMockInitialValues({});
    expect(await AuthService.getToken(), isNull);
    expect(events, contains('credential.disappeared previous=valid origin=none'));
  });

  test('缺失 JWT 时账号 GET 不附带 Bearer，401 不主动清理资料', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', jsonEncode({
      'id': 42, 'username': 'cached', 'nickname': '缓存账号',
      'email': '', 'created_at': '2026-10-21T00:00:00Z',
    }));
    await http.runWithClient(() async {
      await expectLater(
        AuthService.passwordStatus(),
        throwsA(isA<StateError>()),
      );
    }, () => MockClient((request) async {
      expect(request.url.path, '/api/auth/password/status');
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response('{"error":"missing authorization"}', 401);
    }));
    expect((await AuthService.getUser())?.id, 42);
    expect(await AuthService.getToken(), isNull);
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

    await http.runWithClient(() async {
      await AuthService.completeOAuthLogin(result, linkingExisting: true);
      expect(await AuthService.getLastLoginMethod(), 'password');

      await AuthService.completeOAuthLogin(result);
      expect(await AuthService.getLastLoginMethod(), 'github');
      expect((await AuthService.getUser())?.nickname, '测试用户');
    }, () => MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/auth/profile');
      expect(request.headers['authorization'], 'Bearer ${result['token']}');
      return http.Response(jsonEncode(result['user']), 200);
    }));

    await AuthService.logout();
    expect(await AuthService.getLastLoginMethod(), isNull);
  });

  test('GitHub 返回的 JWT 被云端拒绝时不覆盖原有有效登录', () async {
    final oldToken = _jwt(
      exp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600,
    );
    final newToken = _jwt(
      exp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 7200,
    );
    FlutterSecureStorage.setMockInitialValues({'auth_token': oldToken});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_login_method', 'password');
    await prefs.setString('user_data', jsonEncode({
      'id': 1, 'username': 'original', 'nickname': '原账号',
      'email': '', 'created_at': '2026-10-21T00:00:00Z',
    }));
    final result = {
      'token': newToken,
      'user': {
        'id': 2, 'username': 'github_2', 'nickname': '新账号',
        'email': '', 'created_at': '2026-10-21T00:00:00Z',
      },
    };

    await http.runWithClient(() async {
      await expectLater(
        AuthService.completeOAuthLogin(result),
        throwsA(isA<StateError>()),
      );
    }, () => MockClient((request) async {
      expect(request.url.path, '/api/auth/profile');
      expect(request.headers['authorization'], 'Bearer $newToken');
      return http.Response('{"error":"invalid token"}', 401);
    }));

    expect(await AuthService.getToken(), oldToken);
    expect(await AuthService.getLastLoginMethod(), 'password');
    expect((await AuthService.getUser())?.id, 1);
  });

  test('GitHub 凭据与云端账号不一致时拒绝替换登录态', () async {
    final newToken = _jwt(
      exp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600,
    );
    final result = {
      'token': newToken,
      'user': {
        'id': 2, 'username': 'github_2', 'nickname': '新账号',
        'email': '', 'created_at': '2026-10-21T00:00:00Z',
      },
    };
    await http.runWithClient(() async {
      await expectLater(
        AuthService.completeOAuthLogin(result),
        throwsA(isA<StateError>()),
      );
    }, () => MockClient((request) async =>
        http.Response('{"id":3}', 200)));
    expect(await AuthService.getToken(), isNull);
  });

  test('GitHub 绑定状态查询返回 401 时不清除已保存 JWT', () async {
    final token = _jwt(
      exp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600,
    );
    FlutterSecureStorage.setMockInitialValues({'auth_token': token});
    await http.runWithClient(() async {
      await expectLater(AuthService.isGitHubLinked(), throwsA(isA<StateError>()));
    }, () => MockClient((request) async {
      expect(request.url.path, '/api/auth/providers');
      expect(request.headers['authorization'], 'Bearer $token');
      return http.Response('{"error":"invalid token"}', 401);
    }));
    expect(await AuthService.getToken(), token);
  });

  test('账户辅助接口 401 且续期失败不得把尚未过期 JWT 判为退出', () async {
    final token = _jwt(
      exp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600,
    );
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': token,
      'auth_refresh_token': 'rejected-refresh',
    });
    var reads = 0;
    var refreshes = 0;
    await http.runWithClient(() async {
      await expectLater(
        AuthService.isGitHubLinked(),
        throwsA(isA<StateError>()),
      );
      // The provider endpoint's 401 does not revoke an unexpired access JWT.
      // The account view keeps its cached identity and surfaces unknown
      // provider status instead of sending AuthGate back to login.
      expect(await AuthService.isLoggedIn(), isTrue);
      expect(await AuthService.getToken(), token);
    }, () => MockClient((request) async {
      if (request.url.path == '/api/auth/refresh') {
        refreshes++;
        return http.Response('{"error":"session rejected"}', 401);
      }
      expect(request.url.path, '/api/auth/providers');
      reads++;
      expect(request.headers['authorization'], 'Bearer $token');
      return http.Response('{"error":"provider temporarily unavailable"}', 401);
    }));
    expect(reads, 1);
    expect(refreshes, 1);
    expect(await AuthService.getToken(), token);
  });

  test('Legacy token is migrated out of SharedPreferences', () async {
    final token = _jwt(exp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600);
    SharedPreferences.setMockInitialValues({'auth_token': token});

    expect(await AuthService.getToken(), token);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth_token'), isNull);
    expect(await const FlutterSecureStorage().read(key: 'auth_token'), token);
  });
  test('过期 Access Token 刷新一次，侧栏重新读取仍是已登录', () async {
    final events = <String>[];
    AuthService.debugAuthTraceSink = events.add;
    final expired = _jwt(exp:
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - 60);
    final renewed = _jwt(exp:
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600);
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': expired, 'auth_refresh_token': 'first-refresh'});
    var calls = 0;
    await http.runWithClient(() async {
      expect(await AuthService.isLoggedIn(), isTrue);
      expect(await AuthService.isLoggedIn(), isTrue);
      expect(await AuthService.getToken(), renewed);
      expect(await const FlutterSecureStorage().read(key: 'auth_refresh_token'),
          'second-refresh');
    }, () => MockClient((request) async {
      expect(request.url.path, '/api/auth/refresh');
      expect(jsonDecode(request.body)['refresh_token'], 'first-refresh');
      calls++;
      return http.Response(jsonEncode({
        'token': renewed, 'refresh_token': 'second-refresh'}), 200);
    }));
    expect(calls, 1);
    expect(events, contains('refresh.request'));
    expect(events, contains('refresh.response status=200'));
    expect(events, contains('refresh.committed'));
    expect(events.join('\n'), isNot(contains('first-refresh')));
  });

  test('GitHub 候选凭据 401 不以现有账号自动续期', () async {
    final token = _jwt(exp:
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600);
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': token, 'auth_refresh_token': 'current-refresh'});
    final candidate = _jwt(exp:
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 7200);
    var calls = 0;
    await http.runWithClient(() async {
      await expectLater(
        ApiService.verifyOAuthCredential(candidate, 3), throwsStateError);
    }, () => MockClient((request) async {
      calls++;
      expect(request.url.path, '/api/auth/profile');
      return http.Response('{}', 401);
    }));
    expect(calls, 1);
    expect(await AuthService.getToken(), token);
  });

  test('业务接口 401 轮换凭据后最多重试一次', () async {
    final before = _jwt(exp:
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600);
    final after = _jwt(exp:
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 7200);
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': before, 'auth_refresh_token': 'refresh-1'});
    var profileCalls = 0;
    var refreshCalls = 0;
    await http.runWithClient(() async {
      final result = await ApiService.get('/auth/profile');
      expect(result['id'], 8);
    }, () => MockClient((request) async {
      if (request.url.path == '/api/auth/refresh') {
        refreshCalls++;
        return http.Response(jsonEncode({
          'token': after, 'refresh_token': 'refresh-2'}), 200);
      }
      profileCalls++;
      expect(request.headers['authorization'], profileCalls == 1
          ? 'Bearer $before' : 'Bearer $after');
      return profileCalls == 1
          ? http.Response('{}', 401) : http.Response('{"id":8}', 200);
    }));
    expect(refreshCalls, 1);
    expect(profileCalls, 2);
  });

  test('服务端拒绝刷新令牌不应冒充已登录', () async {
    final expired = _jwt(exp:
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - 60);
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': expired, 'auth_refresh_token': 'rejected-refresh'});
    await http.runWithClient(() async {
      expect(await AuthService.isLoggedIn(), isFalse);
    }, () => MockClient((_) async => http.Response('{}', 401)));
    expect(await AuthService.getToken(), expired);
  });

  test('并发刷新共用一次请求，防止 Refresh Token 轮换冲突', () async {
    final expired = _jwt(exp:
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - 60);
    final fresh = _jwt(exp:
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600);
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': expired, 'auth_refresh_token': 'refresh-one'});
    var calls = 0;
    await http.runWithClient(() async {
      final states = await Future.wait([
        AuthService.isLoggedIn(),
        AuthService.isLoggedIn(),
        AuthService.isLoggedIn(),
      ]);
      expect(states, everyElement(isTrue));
    }, () => MockClient((_) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return http.Response(jsonEncode({
        'token': fresh, 'refresh_token': 'refresh-two'}), 200);
    }));
    expect(calls, 1);
  });

}

String _jwt({required int exp}) {
  String part(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'exp': exp})}.signature';
}
