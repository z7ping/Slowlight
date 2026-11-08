import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/ai/ai_config_store.dart';
import 'package:slowlight/ai/ai_models.dart';
import 'package:slowlight/services/api_service.dart';
import 'package:slowlight/services/app_secure_storage.dart';
import 'package:slowlight/services/auth_service.dart';
import 'package:slowlight/services/github_oauth_pending.dart';
import 'package:slowlight/services/local_feishu_config_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('all secrets share the encrypted Android storage configuration', () {
    final options = AppSecureStorage.instance.aOptions.toMap();
    expect(options['encryptedSharedPreferences'], 'true');
    expect(options['resetOnError'], 'false');
    // Do not change the legacy file name or prefix. The existing native
    // plugin migrates those keys to EncryptedSharedPreferences on Android.
    expect(options['sharedPreferencesName'], '');
    expect(options['preferencesKeyPrefix'], '');
    expect(
      identical(GitHubOAuthPending.secureStorage, AppSecureStorage.instance),
      isTrue,
    );
  });

  test('GitHub login survives AI/Feishu reads, OAuth cleanup and token rotation',
      () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final firstToken = _jwt(exp: now + 3600);
    final refreshedToken = _jwt(exp: now + 7200);
    final user = {
      'id': 42,
      'username': 'github_42',
      'nickname': 'Existing user',
      'email': '',
      'created_at': '2026-10-21T00:00:00Z',
    };

    await http.runWithClient(
      () => AuthService.completeOAuthLogin({
        'token': firstToken,
        'refresh_token': 'first-refresh-secret',
        'user': user,
      }),
      () => MockClient((request) async {
        expect(request.url.path, '/api/auth/profile');
        expect(request.headers['authorization'], 'Bearer $firstToken');
        return http.Response(jsonEncode(user), 200);
      }),
    );

    Future<void> verifyAccountRequest() => http.runWithClient(
      () async {
        final profile = await ApiService.get('/auth/profile');
        expect(profile['id'], 42);
      },
      () => MockClient((request) async {
        expect(request.url.path, '/api/auth/profile');
        expect(request.headers['authorization'], 'Bearer $firstToken');
        return http.Response(jsonEncode(user), 200);
      }),
    );
    await verifyAccountRequest();

    final ai = AiConfigStore();
    await ai.saveApiKey(AiProviderType.openai, 'ai-private-key');
    expect(await ai.loadApiKey(AiProviderType.openai), 'ai-private-key');

    final feishu = LocalFeishuConfigStore();
    await feishu.save(appId: 'app-id', appSecret: 'feishu-private-secret');
    expect(await feishu.readSecret(), 'feishu-private-secret');

    await GitHubOAuthPending.save(GitHubOAuthPending(
      sessionId: 'oauth-session',
      pollToken: 'poll-secret',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      endpoint: ApiService.baseUrl,
    ));
    await GitHubOAuthPending.clear(reason: 'login_saved');
    await verifyAccountRequest();

    // A fresh storage wrapper must see the same keys after unrelated reads.
    final reopened = FlutterSecureStorage(
      aOptions: AppSecureStorage.instance.aOptions,
    );
    expect(await reopened.read(key: 'auth_token'), firstToken);
    expect(
      await reopened.read(key: 'auth_refresh_token'),
      'first-refresh-secret',
    );
    expect(await AuthService.isLoggedIn(), isTrue);

    // Simulate expiry and exercise the existing backend refresh contract.
    await reopened.write(key: 'auth_token', value: _jwt(exp: now - 60));
    var refreshRequests = 0;
    await http.runWithClient(() async {
      expect(await AuthService.isLoggedIn(), isTrue);
    }, () => MockClient((request) async {
      expect(request.url.path, '/api/auth/refresh');
      expect(jsonDecode(request.body)['refresh_token'],
          'first-refresh-secret');
      refreshRequests++;
      return http.Response(jsonEncode({
        'token': refreshedToken,
        'refresh_token': 'second-refresh-secret',
      }), 200);
    }));

    expect(refreshRequests, 1);
    expect(await reopened.read(key: 'auth_token'), refreshedToken);
    expect(
      await reopened.read(key: 'auth_refresh_token'),
      'second-refresh-secret',
    );
    expect(await ai.loadApiKey(AiProviderType.openai), 'ai-private-key');
    expect(await feishu.readSecret(), 'feishu-private-secret');
  });
}

String _jwt({required int exp}) {
  String part(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'exp': exp})}.signature';
}
