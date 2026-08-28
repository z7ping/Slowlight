import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/local_product_core_schema.dart';
import '../models/user.dart';
import '../repositories/local_habit_repository.dart';
import '../repositories/local_list_repository.dart';
import 'api_service.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// 登录
  static Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await ApiService.post('/auth/login', body: {
      'username': username,
      'password': password,
    });

    final token = response['token'];
    final user = User.fromJson(response['user']);
    await _saveAuth(token, user);
    return {'token': token, 'user': user};
  }

  /// 注册
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String? nickname,
  }) async {
    final response = await ApiService.post('/auth/register', body: {
      'username': username,
      'email': email,
      'password': password,
      'nickname': nickname ?? username,
    });

    final token = response['token'];
    final user = User.fromJson(response['user']);
    await _saveAuth(token, user);
    return {'token': token, 'user': user};
  }

  /// Token 属于认证凭据，统一存系统安全存储。
  /// 首次读取时会迁移旧版本 SharedPreferences 中的 token。
  static Future<String?> getToken() async {
    final secureToken = await _secureStorage.read(key: _tokenKey);
    if (secureToken != null && secureToken.isNotEmpty) return secureToken;

    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(_tokenKey);
    if (legacyToken == null || legacyToken.isEmpty) return null;

    await _secureStorage.write(key: _tokenKey, value: legacyToken);
    await prefs.remove(_tokenKey);
    return legacyToken;
  }

  static Future<User?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson != null) return User.fromJson(json.decode(userJson));
    return null;
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    if (token == null || token.isEmpty || token.startsWith('local:')) {
      return false;
    }
    return !_isJwtExpired(token);
  }

  static bool _isJwtExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return true;
      final rawExp = payload['exp'];
      final exp = rawExp is num ? rawExp.toInt() : int.tryParse('$rawExp');
      if (exp == null) return true;
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      return exp <= now;
    } catch (_) {
      return true;
    }
  }

  static Future<void> logout() async {
    await _secureStorage.delete(key: _tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey); // 清理旧版本残留。
    await prefs.remove(_userKey);
  }

  /// 本地数据模式初始化 — 创建本地 guest 用户和基础数据。
  /// 不会覆盖已有云端 token。
  static Future<void> initLocalUser() async {
    final existing = await getToken();
    if (existing != null) {
      if (existing.startsWith('local:')) {
        await _createDefaultLists();
        await _createDefaultSystemTags();
        await LocalProductCoreSchema.ensureReady();
        return;
      }
    } else {
      final guest = User(
        id: 0,
        username: 'local_user',
        email: '',
        nickname: '本地用户',
        createdAt: DateTime.now(),
      );
      final ts = DateTime.now().millisecondsSinceEpoch;
      await _saveAuth('local:$ts', guest);
    }

    await _createDefaultLists();
    await _createDefaultSystemTags();
    // 默认四标签是旧版本兼容数据；建立稳定 dimension_key 归属。
    await LocalProductCoreSchema.ensureReady();
  }

  static Future<void> _createDefaultLists() async {
    final listRepo = LocalListRepository();
    final existing = await listRepo.getAll();
    if (existing.isNotEmpty) return;

    final defaults = [
      {'name': '工作', 'icon': '💼', 'color': '#1890ff'},
      {'name': '生活', 'icon': '🏠', 'color': '#52c41a'},
      {'name': '学习', 'icon': '📚', 'color': '#722ed1'},
    ];
    for (final item in defaults) {
      await listRepo.create(
        name: item['name']!,
        icon: item['icon']!,
        color: item['color']!,
      );
    }
  }

  /// 创建默认观察标签。它们保留用于兼容旧 task.system_tag_id，
  /// 但不再等同于 Dimension；dimension_key 由 ProductCoreSchema 回填。
  static Future<void> _createDefaultSystemTags() async {
    final habitRepo = LocalHabitRepository();
    final existing = await habitRepo.getSystemTags();
    if (existing.isNotEmpty) return;

    final defaults = [
      {'name': '身体', 'icon': '💪', 'color': '#52c41a'},
      {'name': '认知', 'icon': '🧠', 'color': '#1890ff'},
      {'name': '产出', 'icon': '🎯', 'color': '#722ed1'},
      {'name': '关系', 'icon': '❤️', 'color': '#eb2f96'},
    ];
    for (final item in defaults) {
      await habitRepo.createSystemTag(
        name: item['name']!,
        icon: item['icon']!,
        color: item['color']!,
      );
    }
  }

  static Future<bool> isLocalMode() async {
    final token = await getToken();
    return token != null && token.startsWith('local:');
  }

  static Future<void> _saveAuth(String token, User user) async {
    await _secureStorage.write(key: _tokenKey, value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey); // 不再让认证凭据落入普通偏好存储。
    await prefs.setString(_userKey, json.encode(user.toJson()));
  }
}
