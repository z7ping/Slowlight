import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_storage_config.dart';

/// Local Data 模式的飞书配置。Secret 只存系统安全存储。
class LocalFeishuConfigStore {
  static const _metadataKey = 'local_feishu_config';
  static const _secretKey = 'local_feishu_app_secret';
  final FlutterSecureStorage _secrets = slowlightSecureStorage;

  Future<Map<String, dynamic>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_metadataKey);
    if (raw == null) return {'configured': false};
    final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final hasSecret = await _secrets.read(key: _secretKey) != null;
    return {
      ...data,
      'configured':
          hasSecret && (data['app_id']?.toString().isNotEmpty ?? false)
    };
  }

  Future<void> save(
      {required String appId,
      required String appSecret,
      String? tableUrl}) async {
    await _secrets.write(key: _secretKey, value: appSecret);
    final prefs = await SharedPreferences.getInstance();
    final existing = await load();
    final nextUrl = tableUrl ?? '';
    // A different app or Bitable must not inherit table IDs from the old target.
    final sameTarget =
        existing['app_id']?.toString() == appId &&
        existing['table_url']?.toString() == nextUrl;
    await prefs.setString(
        _metadataKey,
        jsonEncode({
          'app_id': appId,
          'table_url': nextUrl,
          'tables': sameTarget
              ? (existing['tables'] ?? <String, dynamic>{})
              : <String, dynamic>{}
        }));
  }

  Future<String?> readSecret() => _secrets.read(key: _secretKey);

  Future<void> saveTables(Map<String, String> tables,
      {String? tableUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await load();
    await prefs.setString(
        _metadataKey,
        jsonEncode({
          'app_id': existing['app_id'] ?? '',
          'table_url': tableUrl ?? existing['table_url'] ?? '',
          'tables': tables
        }));
  }
}
