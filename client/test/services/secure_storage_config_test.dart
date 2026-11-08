import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/ai/ai_config_store.dart';
import 'package:slowlight/ai/ai_models.dart';
import 'package:slowlight/services/auth_service.dart';
import 'package:slowlight/services/github_oauth_pending.dart';
import 'package:slowlight/services/local_feishu_config_store.dart';
import 'package:slowlight/services/secure_storage_config.dart';
import 'package:slowlight/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('Android secret storage uses exactly one encrypted namespace', () {
    final options = slowlightSecureStorage.aOptions.toMap();
    expect(options['encryptedSharedPreferences'], 'true');
    expect(options['resetOnError'], 'false');
    // Preserve the plugin's original file name/prefix so it can migrate old
    // defaults in place instead of silently switching to a new namespace.
    expect(options['sharedPreferencesName'], '');
    expect(options['preferencesKeyPrefix'], '');
    expect(
      identical(GitHubOAuthPending.secureStorage, slowlightSecureStorage),
      isTrue,
    );
  });

  test('reading AI keys and removing OAuth pending keeps both JWTs', () async {
    const access = 'sample-access';
    const refresh = 'sample-refresh';
    await slowlightSecureStorage.write(key: 'auth_token', value: access);
    await slowlightSecureStorage.write(
      key: 'auth_refresh_token',
      value: refresh,
    );

    final aiStore = AiConfigStore();
    await aiStore.saveApiKey(AiProviderType.deepseek, 'sk-example');
    expect(await aiStore.loadApiKey(AiProviderType.deepseek), 'sk-example');

    final pending = GitHubOAuthPending(
      sessionId: 'session',
      pollToken: 'poll',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      endpoint: ApiService.baseUrl,
    );
    await GitHubOAuthPending.save(pending);
    expect(await GitHubOAuthPending.load(), isNotNull);
    await GitHubOAuthPending.clear(reason: 'login_saved');

    final feishu = LocalFeishuConfigStore();
    await feishu.save(appId: 'app-test', appSecret: 'secret-test');
    expect(await feishu.readSecret(), 'secret-test');

    expect(await AuthService.getToken(), access);
    expect(
      await slowlightSecureStorage.read(key: 'auth_refresh_token'),
      refresh,
    );
    expect(
      await slowlightSecureStorage.read(key: 'github_oauth_pending'),
      isNull,
    );
  });
}
