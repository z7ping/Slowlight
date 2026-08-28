import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_models.dart';

abstract interface class AiSecretStore {
  Future<String?> read(AiProviderType provider);
  Future<void> write(AiProviderType provider, String value);
  Future<void> delete(AiProviderType provider);
}

class SecureAiSecretStore implements AiSecretStore {
  final FlutterSecureStorage _storage;

  SecureAiSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            FlutterSecureStorage(
              aOptions: const AndroidOptions(encryptedSharedPreferences: true),
            );

  String _key(AiProviderType provider) => 'slowlight.ai.api_key.${provider.wireName}';

  @override
  Future<String?> read(AiProviderType provider) => _storage.read(key: _key(provider));

  @override
  Future<void> write(AiProviderType provider, String value) async {
    final key = value.trim();
    if (key.isEmpty) {
      await delete(provider);
      return;
    }
    await _storage.write(key: _key(provider), value: key);
  }

  @override
  Future<void> delete(AiProviderType provider) => _storage.delete(key: _key(provider));
}

class AiConfigStore {
  static const _configKey = 'slowlight.ai.config.v1';
  final AiSecretStore secrets;

  AiConfigStore({AiSecretStore? secrets})
      : secrets = secrets ?? SecureAiSecretStore();

  Future<AiConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw == null || raw.isEmpty) return const AiConfig();
    try {
      final value = jsonDecode(raw);
      if (value is Map) {
        return AiConfig.fromJson(Map<String, dynamic>.from(value));
      }
    } catch (_) {}
    return const AiConfig();
  }

  Future<void> save(AiConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config.toJson()));
  }

  Future<String?> loadApiKey(AiProviderType provider) => secrets.read(provider);

  Future<void> saveApiKey(AiProviderType provider, String key) =>
      secrets.write(provider, key);

  Future<void> clearApiKey(AiProviderType provider) => secrets.delete(provider);
}
