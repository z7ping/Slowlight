import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_models.dart';
import '../services/secure_storage_config.dart';

abstract interface class AiSecretStore {
  Future<String?> read(AiProviderType provider);
  Future<void> write(AiProviderType provider, String value);
  Future<void> delete(AiProviderType provider);
}

class SecureAiSecretStore implements AiSecretStore {
  final FlutterSecureStorage _storage;

  SecureAiSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? slowlightSecureStorage;

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


/// Separate secure-storage namespace for multiple configurations of one provider.
abstract interface class AiProfileSecretStore {
  Future<String?> read(String profileId);
  Future<void> write(String profileId, String key);
  Future<void> delete(String profileId);
}

class SecureAiProfileSecretStore implements AiProfileSecretStore {
  final FlutterSecureStorage _storage;

  SecureAiProfileSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? slowlightSecureStorage;

  String _key(String id) => 'slowlight.ai.profile_key.$id';

  @override
  Future<String?> read(String profileId) =>
      _storage.read(key: _key(profileId));

  @override
  Future<void> write(String profileId, String key) =>
      _storage.write(key: _key(profileId), value: key.trim());

  @override
  Future<void> delete(String profileId) =>
      _storage.delete(key: _key(profileId));
}

class AiConfigStore {
  static const _configKey = 'slowlight.ai.config.v1';
  static const _profilesKey = 'slowlight.ai.profiles.v1';
  final AiSecretStore secrets;
  final AiProfileSecretStore profileSecrets;

  AiConfigStore({AiSecretStore? secrets, AiProfileSecretStore? profileSecrets})
      : secrets = secrets ?? SecureAiSecretStore(),
        profileSecrets = profileSecrets ?? SecureAiProfileSecretStore();

  /// Existing AI consumers always receive the one active configuration.
  /// The old v1 key is retained for upgrades and existing integrations.
  Future<AiConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_profilesKey)) {
      final catalog = await loadCatalog();
      final active = catalog.active;
      return (active?.config ?? const AiConfig())
          .copyWith(enabled: catalog.enabled && active != null);
    }
    return _loadLegacy();
  }

  Future<AiConfig> _loadLegacy() async {
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

  /// Migrates the v1 active config in memory without rewriting credentials.
  Future<AiProfileCatalog> loadCatalog() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw != null) {
      final value = jsonDecode(raw);
      if (value is! Map) throw const FormatException('Invalid AI catalog');
      return AiProfileCatalog.fromJson(Map<String, dynamic>.from(value));
    }
    final old = await _loadLegacy();
    return AiProfileCatalog(
      profiles: [
        AiProfile(
          id: 'legacy',
          name: '${old.provider.label} · 默认',
          config: old.copyWith(enabled: false),
        ),
      ],
      activeId: 'legacy',
      enabled: old.enabled,
    );
  }

  Future<String?> loadProfileKey(AiProfile profile) =>
      profile.id == 'legacy'
          ? secrets.read(profile.config.provider)
          : profileSecrets.read(profile.id);

  Future<void> _putProfileKey(AiProfile profile, String? key) async {
    if (profile.id == 'legacy') {
      if (key == null || key.isEmpty) {
        await secrets.delete(profile.config.provider);
      } else {
        await secrets.write(profile.config.provider, key);
      }
    } else if (key == null || key.isEmpty) {
      await profileSecrets.delete(profile.id);
    } else {
      await profileSecrets.write(profile.id, key);
    }
  }

  /// Secure key change first, catalog commit second. Restore the previous key
  /// on commit failure; never write credentials to SharedPreferences.
  Future<void> saveCatalog(
    AiProfileCatalog catalog, {
    AiProfile? secretProfile,
    String? newApiKey,
    bool clearKey = false,
    AiProfile? deletedProfile,
  }) async {
    if (secretProfile != null && deletedProfile != null) {
      throw ArgumentError('Only one key mutation per catalog commit');
    }
    final target = deletedProfile ?? secretProfile;
    final needsKeyMutation =
        deletedProfile != null || clearKey || (newApiKey?.trim().isNotEmpty ?? false);
    String? previous;
    if (needsKeyMutation && target != null) {
      previous = await loadProfileKey(target);
      await _putProfileKey(target,
          deletedProfile != null || clearKey ? null : newApiKey!.trim());
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(_profilesKey, jsonEncode(catalog.toJson()))) {
        throw StateError('AI 配置持久化失败');
      }
    } catch (_) {
      if (needsKeyMutation && target != null) {
        try {
          await _putProfileKey(target, previous);
        } catch (_) {
          throw StateError('AI 配置保存失败，密钥恢复失败，请重新核对');
        }
      }
      rethrow;
    }
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

  Future<String?> loadApiKey(AiProviderType provider) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_profilesKey)) {
      final active = (await loadCatalog()).active;
      if (active != null && active.config.provider == provider) {
        return loadProfileKey(active);
      }
      // Missing active profile is not permission to read an unrelated key.
      return null;
    }
    return secrets.read(provider);
  }

  Future<void> saveApiKey(AiProviderType provider, String key) =>
      secrets.write(provider, key);

  Future<void> clearApiKey(AiProviderType provider) => secrets.delete(provider);
}
