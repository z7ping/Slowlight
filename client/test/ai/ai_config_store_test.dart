import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/ai/ai_config_store.dart';
import 'package:slowlight/ai/ai_models.dart';

class FakeSecretStore implements AiSecretStore {
  final values = <AiProviderType, String>{};
  bool failNextWrite = false;

  @override
  Future<void> delete(AiProviderType provider) async => values.remove(provider);

  @override
  Future<String?> read(AiProviderType provider) async => values[provider];

  @override
  Future<void> write(AiProviderType provider, String value) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('secure store unavailable');
    }
    values[provider] = value;
  }
}

class FakeProfileSecrets implements AiProfileSecretStore {
  final values = <String, String>{};
  bool failWrite = false;

  @override
  Future<String?> read(String id) async => values[id];

  @override
  Future<void> write(String id, String key) async {
    if (failWrite) throw StateError('blocked');
    values[id] = key;
  }

  @override
  Future<void> delete(String id) async {
    values.remove(id);
  }
}

class _FailingConfigStore extends AiConfigStore {
  _FailingConfigStore({required super.secrets});

  @override
  Future<void> save(AiConfig config) async =>
      throw StateError('preferences unavailable');
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
  test('credential write failure never publishes new active configuration', () async {
    final secrets = FakeSecretStore()..failNextWrite = true;
    final store = AiConfigStore(secrets: secrets);
    final candidate = const AiConfig(
      enabled: true,
      provider: AiProviderType.openai,
      model: 'test-model',
    );

    await expectLater(
      store.saveConfiguration(candidate, newApiKey: 'secret-new'),
      throwsStateError,
    );
    expect((await store.load()).enabled, false);
    expect(await store.loadApiKey(AiProviderType.openai), isNull);
  });

  test('preference commit failure restores the previous provider credential', () async {
    final secrets = FakeSecretStore();
    await secrets.write(AiProviderType.deepseek, 'secret-original');
    final store = _FailingConfigStore(secrets: secrets);
    await expectLater(
      store.saveConfiguration(
        const AiConfig(enabled: true, provider: AiProviderType.deepseek),
        newApiKey: 'secret-next',
      ),
      throwsStateError,
    );
    expect(await store.loadApiKey(AiProviderType.deepseek), 'secret-original');
    expect((await store.load()).enabled, false);
  });

  test('credential preservation and all four provider configurations use one store', () async {
    final secrets = FakeSecretStore();
    final store = AiConfigStore(secrets: secrets);
    for (final provider in AiProviderType.values) {
      final config = AiConfig(
        enabled: true,
        provider: provider,
        endpoint: 'https://example.org/v1',
        model: 'example-model',
      );
      await store.saveConfiguration(
        config,
        newApiKey: provider.apiKeyRequired ? 'secret-' + provider.name : null,
      );
      expect((await store.load()).provider, provider);
    }
    expect(await store.loadApiKey(AiProviderType.openai), 'secret-openai');
    expect(await store.loadApiKey(AiProviderType.deepseek), 'secret-deepseek');
    expect(await store.loadApiKey(AiProviderType.compatible), isNull);
    expect(AiProviderType.compatible.apiKeyRequired, false);
    expect(AiProviderType.ollama.apiKeyRequired, false);
  });

  test('v1 settings become one legacy profile without losing its credential', () async {
    final secrets = FakeSecretStore();
    final store = AiConfigStore(secrets: secrets,
        profileSecrets: FakeProfileSecrets());
    await store.save(const AiConfig(
      enabled: true, provider: AiProviderType.openai,
      model: 'existing', endpoint: 'https://api.openai.com/v1',
    ));
    await secrets.write(AiProviderType.openai, 'old-key');
    final catalog = await store.loadCatalog();
    expect(catalog.profiles.length, 1);
    expect(catalog.activeId, 'legacy');
    expect(catalog.enabled, true);
    expect(await store.loadProfileKey(catalog.active!), 'old-key');
    expect((await store.load()).model, 'existing');
  });

  test('same provider profiles have separate keys and only active config loads', () async {
    final secrets = FakeProfileSecrets();
    final store = AiConfigStore(
      secrets: FakeSecretStore(), profileSecrets: secrets,
    );
    const a = AiProfile(
      id: 'a', name: 'Local', config: AiConfig(
        provider: AiProviderType.openai, endpoint: 'https://one.test/v1', model: 'a',
      ),
    );
    const b = AiProfile(
      id: 'b', name: 'Backup', config: AiConfig(
        provider: AiProviderType.openai, endpoint: 'https://two.test/v1', model: 'b',
      ),
    );
    await store.saveCatalog(const AiProfileCatalog(
      profiles: [a,b], activeId: 'a', enabled: true,
    ), secretProfile: a, newApiKey: 'secret-one');
    await store.saveCatalog(const AiProfileCatalog(
      profiles: [a,b], activeId: 'a', enabled: true,
    ), secretProfile: b, newApiKey: 'secret-two');
    expect((await store.load()).model, 'a');
    expect(await store.loadApiKey(AiProviderType.openai), 'secret-one');
    await store.saveCatalog(const AiProfileCatalog(
      profiles: [a,b], activeId: 'b', enabled: true,
    ));
    expect((await store.load()).model, 'b');
    expect(await store.loadApiKey(AiProviderType.openai), 'secret-two');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('slowlight.ai.profiles.v1'), isNot(contains('secret-one')));
    expect(prefs.getString('slowlight.ai.profiles.v1'), isNot(contains('secret-two')));
  });

  test('removing active profile disables AI instead of activating another', () async {
    final secrets = FakeProfileSecrets();
    final store = AiConfigStore(
      secrets: FakeSecretStore(), profileSecrets: secrets,
    );
    const a = AiProfile(
      id: 'one', name: 'One', config: AiConfig(model:'one'),
    );
    const b = AiProfile(
      id: 'two', name: 'Two', config: AiConfig(model:'two'),
    );
    await store.saveCatalog(const AiProfileCatalog(
      profiles:[a,b], activeId:'one', enabled:true,
    ), secretProfile:a, newApiKey:'one-key');
    await store.saveCatalog(const AiProfileCatalog(
      profiles:[b], activeId:null, enabled:false,
    ), deletedProfile:a);
    final catalog = await store.loadCatalog();
    expect(catalog.activeId, isNull);
    expect(catalog.enabled, false);
    expect((await store.load()).enabled, false);
    expect(secrets.values.containsKey('one'), false);
  });

  test('credential failure cannot publish a new active profile', () async {
    final secrets = FakeProfileSecrets()..failWrite = true;
    final store = AiConfigStore(
      secrets: FakeSecretStore(), profileSecrets: secrets,
    );
    const selected = AiProfile(
      id:'p1', name:'Test', config:AiConfig(model:'test'),
    );
    await expectLater(store.saveCatalog(const AiProfileCatalog(
      profiles:[selected], activeId:'p1', enabled:true,
    ), secretProfile:selected, newApiKey:'secret'), throwsStateError);
    expect((await store.load()).enabled, false);
    expect((await store.loadCatalog()).profiles.single.id, 'legacy');
  });

}
