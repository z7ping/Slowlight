import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/ai/ai_config_store.dart';
import 'package:slowlight/ai/ai_models.dart';

class FakeSecretStore implements AiSecretStore {
  final values = <AiProviderType, String>{};

  @override
  Future<void> delete(AiProviderType provider) async => values.remove(provider);

  @override
  Future<String?> read(AiProviderType provider) async => values[provider];

  @override
  Future<void> write(AiProviderType provider, String value) async {
    values[provider] = value;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('non-secret config persists in SharedPreferences', () async {
    final secrets = FakeSecretStore();
    final store = AiConfigStore(secrets: secrets);
    const config = AiConfig(
      enabled: true,
      provider: AiProviderType.compatible,
      endpoint: 'http://127.0.0.1:9000/v1',
      model: 'my-model',
      temperature: 0.3,
      maxTokens: 500,
    );

    await store.save(config);
    final loaded = await store.load();

    expect(loaded.enabled, true);
    expect(loaded.provider, AiProviderType.compatible);
    expect(loaded.endpoint, 'http://127.0.0.1:9000/v1');
    expect(loaded.model, 'my-model');
  });

  test('API key is stored only through secret store', () async {
    final secrets = FakeSecretStore();
    final store = AiConfigStore(secrets: secrets);

    await store.save(const AiConfig(
      enabled: true,
      provider: AiProviderType.deepseek,
      endpoint: 'https://api.deepseek.com',
      model: 'deepseek-v4-pro',
    ));
    await store.saveApiKey(AiProviderType.deepseek, 'sk-secret');

    final prefs = await SharedPreferences.getInstance();
    final allPrefs = prefs.getKeys()
        .map((key) => prefs.get(key)?.toString() ?? '')
        .join('\n');

    expect(allPrefs, isNot(contains('sk-secret')));
    expect(await store.loadApiKey(AiProviderType.deepseek), 'sk-secret');
  });
}
