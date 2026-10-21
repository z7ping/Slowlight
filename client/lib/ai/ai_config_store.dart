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
    if (!await prefs.setString(_configKey, jsonEncode(config.toJson()))) {
      throw StateError('AI 配置持久化失败');
    }
  }

  /// 密钥变更必须先成功，再提交非敏感的生效配置。
  /// 若第二阶段失败，尽力恢复原密钥；不会把密钥写入偏好设置。
  /// 跨两种系统存储无法保证进程崩溃时的原子性，失败时 UI 不得宣称保存成功。
  Future<void> saveConfiguration(AiConfig config, {String? newApiKey}) async {
    final nextKey = newApiKey?.trim();
    if (nextKey == null || nextKey.isEmpty) {
      await save(config);
      return;
    }
    final previousKey = await loadApiKey(config.provider);
    await saveApiKey(config.provider, nextKey);
    try {
      await save(config);
    } catch (_) {
      try {
        if (previousKey == null || previousKey.isEmpty) {
          await clearApiKey(config.provider);
        } else {
          await saveApiKey(config.provider, previousKey);
        }
      } catch (_) {
        throw StateError('AI 配置保存失败，密钥恢复失败，请重新检查当前服务商密钥');
      }
      rethrow;
    }
  }

  Future<String?> loadApiKey(AiProviderType provider) => secrets.read(provider);

  Future<void> saveApiKey(AiProviderType provider, String key) =>
      secrets.write(provider, key);

  Future<void> clearApiKey(AiProviderType provider) => secrets.delete(provider);
}
