import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/local_product_core_schema.dart';
import '../models/user.dart';
import '../repositories/local_habit_repository.dart';
import '../repositories/local_list_repository.dart';
import 'api_service.dart';
import 'app_error_logger.dart';
import 'auth_storage_diagnostics.dart';
import 'secure_storage_config.dart';
import 'http_util.dart';

class SessionRefreshRejected implements Exception {
  const SessionRefreshRejected();
}

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const Duration _refreshAhead = Duration(minutes: 5);
  static Future<String?>? _refreshInFlight;
  static int _credentialEpoch = 0;
  static const String _userKey = 'user_data';
  static const String _loginMethodKey = 'auth_login_method';
  static const _secureStorage = slowlightSecureStorage;

  static Future<String?> _readStorage(
    AuthStorageSlot slot,
    String actor, {
    bool logPresent = false,
  }) =>
      AuthStorageDiagnostics.read(
        _secureStorage,
        slot: slot,
        actor: actor,
        logPresent: logPresent,
      );

  static Future<void> _writeStorage(
    AuthStorageSlot slot, String value, String actor,
  ) =>
      AuthStorageDiagnostics.write(
        _secureStorage, slot: slot, value: value, actor: actor,
      );

  static Future<void> _deleteStorage(
    AuthStorageSlot slot, String actor,
  ) =>
      AuthStorageDiagnostics.delete(
        _secureStorage, slot: slot, actor: actor,
      );

  // Only categorical, credential-free events are sent here. No JWT/refresh
  // value, user ID, account name, HTTP payload or endpoint query is recorded.
  @visibleForTesting
  static void Function(String)? debugAuthTraceSink;
  static String? _lastTokenState;
  static bool _missingStorageProbed = false;

  static Future<void> _probeMissingStorageOnce() async {
    if (_missingStorageProbed) return;
    _missingStorageProbed = true;
    // Presence-only probes after a confirmed missing access credential.
    // A single event per loss episode, never per failed HTTP request.
    await AuthStorageDiagnostics.checkpoint(
      _secureStorage,
      slot: AuthStorageSlot.refresh,
      actor: 'access_missing.companion_refresh',
    );
    await AuthStorageDiagnostics.checkpoint(
      _secureStorage,
      slot: AuthStorageSlot.oauthPending,
      actor: 'access_missing.companion_pending',
    );
  }

  static void _trace(String event) {
    try {
      debugAuthTraceSink?.call(event);
    } catch (_) {
      // Diagnostics must never interrupt sign-in or secure storage writes.
    }
    unawaited(AppErrorLogger.instance.write(
      source: 'AuthSession',
      error: event,
    ));
  }

  static void _observeToken(String? value, String origin) {
    final state = value == null
        ? 'missing'
        : value.startsWith('local:')
            ? 'local'
            : _isJwtExpired(value)
                ? 'invalid_or_expired'
                : 'valid';
    if (_lastTokenState != state) {
      // A previously valid JWT read as missing; record only the transition.
      // Correlate with logout events before attributing any cause.
      if (_lastTokenState == 'valid' && state == 'missing' &&
          origin == 'none') {
        _trace('credential.disappeared previous=valid origin=none');
      }
      _lastTokenState = state;
      // "state=" is intentionally reserved for redacting OAuth state secrets.
      _trace('credential.read origin=$origin status=$state');
    }
  }

  /// 登录
  static Future<Map<String, dynamic>> login(String username, String password) async {
    ApiService.validateCloudEndpoint();
    final response = await ApiService.post('/auth/login', body: {
      'username': username,
      'password': password,
    });

    final token = response['token'];
    final user = User.fromJson(response['user']);
    await _saveAuth(
      token, user,
      refreshToken: response['refresh_token'] as String?,
      loginMethod: 'password',
    );
    return {'token': token, 'user': user};
  }

  /// 注册
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String? nickname,
  }) async {
    ApiService.validateCloudEndpoint();
    final response = await ApiService.post('/auth/register', body: {
      'username': username,
      'email': email,
      'password': password,
      'nickname': nickname ?? username,
    });

    final token = response['token'];
    final user = User.fromJson(response['user']);
    await _saveAuth(
      token, user,
      refreshToken: response['refresh_token'] as String?,
      loginMethod: 'password',
    );
    return {'token': token, 'user': user};
  }

  /// OAuth 登录沿用原有用户模型、JWT 和系统安全存储。
  static Future<void> completeOAuthLogin(
    Map<String, dynamic> result, {
    bool linkingExisting = false,
  }) async {
    final token = result['token'];
    final userJson = result['user'];
    if (token is! String || token.isEmpty || userJson is! Map) {
      throw StateError('GitHub 登录结果缺少有效凭据');
    }
    final user = User.fromJson(Map<String, dynamic>.from(userJson));
    // OAuth poll 的 complete 仅证明 GitHub 授权完成，不证明新 JWT
    // 已被业务接口接受。先核验再替换，避免绑定/登录后把有效会话覆盖为 401。
    final candidateRefresh = result['refresh_token'];
    final refreshStatus =
        candidateRefresh is String && candidateRefresh.isNotEmpty
            ? 'present'
            : 'absent';
    _trace('oauth.complete_received mode=${linkingExisting ? 'binding' : 'signin'} '
        'access=present refresh=$refreshStatus');
    await ApiService.verifyOAuthCredential(token, user.id);
    await _saveAuth(
      token,
      user,
      refreshToken: result['refresh_token'] as String?,
      loginMethod: linkingExisting ? await getLastLoginMethod() : 'github',
    );
  }

  /// Token 属于认证凭据，统一存系统安全存储。
  /// 首次读取时会迁移旧版本 SharedPreferences 中的 token。
  static Future<String?> getToken({String source = 'general'}) async {
    try {
      final secureToken = await _readStorage(
        AuthStorageSlot.access,
        'get_token.$source',
        logPresent: source != 'http_request' && source != 'general',
      );
      if (secureToken != null && secureToken.isNotEmpty) {
        _missingStorageProbed = false;
        _observeToken(secureToken, 'secure');
        return secureToken;
      }

      final prefs = await SharedPreferences.getInstance();
      final legacyToken = prefs.getString(_tokenKey);
      if (legacyToken == null || legacyToken.isEmpty) {
        if (_lastTokenState == 'valid') {
          // One extra read only after a previously valid credential disappears.
          // Never restore a token from memory or an unverified cache.
          final confirmedToken = await _readStorage(
            AuthStorageSlot.access, 'get_token.retry.$source',
            logPresent: true,
          );
          if (confirmedToken != null && confirmedToken.isNotEmpty) {
            _trace('credential.read_retry result=recovered');
            _missingStorageProbed = false;
            _observeToken(confirmedToken, 'secure_retry');
            return confirmedToken;
          }
        }
        _observeToken(null, 'none');
        await _probeMissingStorageOnce();
        return null;
      }

      await _writeStorage(AuthStorageSlot.access, legacyToken, 'legacy_migration');
      await prefs.remove(_tokenKey);
      _trace('credential.legacy_migrated');
      _missingStorageProbed = false;
      _observeToken(legacyToken, 'legacy');
      return legacyToken;
    } catch (error) {
      _trace('credential.read_failed kind=${error.runtimeType}');
      rethrow;
    }
  }

  /// 后端持久绑定表是唯一可信的第三方关联依据。请求失败必须视为未知。
  static Future<bool> isGitHubLinked() async {
    final data = await ApiService.get('/auth/providers');
    if (data['github'] is! bool) {
      throw const FormatException('GitHub 账号绑定状态无效');
    }
    return data['github'] as bool;
  }

  /// 只描述这台设备上最近的登录方式，不等于第三方绑定是否仍有效。
  static Future<String?> getLastLoginMethod() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_loginMethodKey);
  }

  static Future<User?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson != null) return User.fromJson(json.decode(userJson));
    return null;
  }

  /// 服务端为资料真相；成功读取后才更新本机缓存，不改变 JWT/登录方式。
  static Future<User> refreshCloudUser() async {
    ApiService.validateCloudEndpoint();
    final token = await getToken(source: 'account_profile');
    final data = await ApiService.get('/auth/profile');
    if (token == null || token != await getToken()) {
      throw StateError('账号已切换，已取消过期的资料更新');
    }
    final user = User.fromJson(data);
    await _cacheUser(user);
    return user;
  }

  static Future<User> updateNickname(String nickname) async {
    ApiService.validateCloudEndpoint();
    final token = await getToken(source: 'account_edit');
    final data = await ApiService.patchAccountProfile({
      'nickname': nickname.trim(),
    });
    if (token == null || token != await getToken()) {
      throw StateError('账号已切换，请重新检查云端资料');
    }
    final user = User.fromJson(data);
    await _cacheUser(user);
    return user;
  }

  static Future<Map<String, dynamic>> passwordStatus() =>
      ApiService.get('/auth/password/status');

  /// OAuth 用户需先完成 GitHub 身份验证，签发五分钟内的 GitHub JWT。
  static Future<void> setupPassword({
    required String username,
    required String password,
  }) async {
    ApiService.validateCloudEndpoint();
    await ApiService.post('/auth/password/setup', authenticated: true, body: {
      'username': username.trim(),
      'password': password,
    });
    await refreshCloudUser();
  }

  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    ApiService.validateCloudEndpoint();
    await ApiService.post('/auth/password/change', authenticated: true, body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  static Future<void> _cacheUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, json.encode(user.toJson()));
  }

  // 凭据是唯一身份事实；读存储失败或网络故障不能冒充“未登录”。
  static Future<bool> isLoggedIn() async {
    final token = await getToken(source: 'auth_check');
    if (token != null && token.startsWith('local:')) return false;
    if (token != null && !_isJwtExpired(token)) return true;
    if (await _readStorage(
          AuthStorageSlot.refresh, 'auth_check', logPresent: true,
        ) == null) {
      _trace('session.check result=login_required reason=no_refresh');
      return false;
    }
    try {
      final renewed = await refreshAccessToken();
      return renewed != null && !_isJwtExpired(renewed);
    } on SessionRefreshRejected {
      return false;
    }
  }

  static int? _jwtExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;
      final raw = payload['exp'];
      return raw is num ? raw.toInt() : int.tryParse('$raw');
    } catch (_) {
      return null;
    }
  }

  static bool _isJwtExpired(String token) =>
      _jwtExpiresWithin(token, Duration.zero);

  static bool _jwtExpiresWithin(String token, Duration time) {
    final exp = _jwtExpiry(token);
    if (exp == null) return true;
    final cutoff =
        DateTime.now().toUtc().add(time).millisecondsSinceEpoch ~/ 1000;
    return exp <= cutoff;
  }

  // 业务请求在剩余五分钟内提前续期；同进程只轮换一次。
  static Future<String?> getTokenForRequest() async {
    final token = await getToken(source: 'http_request');
    if (token != null && (token.startsWith('local:') ||
        !_jwtExpiresWithin(token, _refreshAhead))) return token;
    if (await _readStorage(AuthStorageSlot.refresh, 'http_request') == null) return token;
    try {
      return await refreshAccessToken() ?? token;
    } catch (_) {
      // 离线继续保留凭据，网络错误由请求调用方处理。
      return token;
    }
  }

  // 只重试当前会话的 Bearer Token，不以旧登录身份验证 OAuth 候选令牌。
  static Future<String?> recoverUnauthorized(String attemptedToken) async {
    final stored = await getToken(source: 'http401_recovery');
    if (stored == null || stored.startsWith('local:')) {
      _trace('http401.recovery result=no_cloud_credential');
      return null;
    }
    if (stored != attemptedToken) {
      _trace('http401.recovery result=changed_during_request');
      return _isJwtExpired(stored) ? null : stored;
    }
    _trace('http401.recovery result=refresh_attempt');
    try {
      final renewed = await refreshAccessToken();
      _trace(renewed == null
          ? 'http401.recovery result=no_refresh'
          : 'http401.recovery result=refreshed');
      return renewed != attemptedToken ? renewed : null;
    } on SessionRefreshRejected {
      _trace('http401.recovery result=refresh_rejected');
      // A 401 from an auxiliary endpoint (providers/password/status) and a
      // rejected refresh request are not proof that an unexpired access JWT
      // was revoked. Leave session policy to AuthGate / token expiration;
      // never turn an account-info read failure into an implicit logout.
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> refreshAccessToken() async {
    final pending = _refreshInFlight;
    if (pending != null) return pending;
    final operation = _performRefresh();
    _refreshInFlight = operation;
    try {
      return await operation;
    } finally {
      if (identical(_refreshInFlight, operation)) _refreshInFlight = null;
    }
  }

  static Future<String?> _performRefresh() async {
    String? previous;
    try {
      previous = await _readStorage(
        AuthStorageSlot.refresh, 'refresh.begin', logPresent: true,
      );
    } catch (error) {
      _trace('refresh.storage_read_failed kind=${error.runtimeType}');
      rethrow;
    }
    if (previous == null || previous.isEmpty) {
      _trace('refresh.skipped reason=missing_refresh');
      return null;
    }
    _trace('refresh.request');
    final epoch = _credentialEpoch;
    late final http.Response response;
    try {
      response = await HttpUtil.post(
        Uri.parse('${ApiService.baseUrl}/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': previous}),
      ).timeout(ApiService.postTimeout);
    } catch (error) {
      _trace('refresh.transport_failed kind=${error.runtimeType}');
      rethrow;
    }
    _trace('refresh.response status=${response.statusCode}');
    if (response.statusCode == 400 || response.statusCode == 401) {
      throw const SessionRefreshRejected();
    }
    if (response.statusCode != 200) {
      throw StateError('续期服务暂时不可用（HTTP ${response.statusCode}）');
    }
    final data = jsonDecode(response.body);
    if (data is! Map ||
        data['token'] is! String || data['refresh_token'] is! String ||
        (data['refresh_token'] as String).isEmpty ||
        _isJwtExpired(data['token'] as String)) {
      throw const FormatException('续期响应无效');
    }
    // 异步返回后若已退出/换账号，不可复活旧身份。
    if (epoch != _credentialEpoch ||
        await _readStorage(
          AuthStorageSlot.refresh, 'refresh.guard', logPresent: true,
        ) != previous) {
      _trace('refresh.discarded reason=session_changed');
      return getToken();
    }
    final newToken = data['token'] as String;
    final newRefresh = data['refresh_token'] as String;
    await _writeStorage(AuthStorageSlot.refresh, newRefresh, 'refresh.rotate');
    await _writeStorage(AuthStorageSlot.access, newToken, 'refresh.rotate');
    if (await _readStorage(
          AuthStorageSlot.access, 'refresh.verify', logPresent: true,
        ) != newToken ||
        await _readStorage(
          AuthStorageSlot.refresh, 'refresh.verify', logPresent: true,
        ) != newRefresh) {
      throw StateError('更新登录凭据失败');
    }
    _credentialEpoch++;
    _missingStorageProbed = false;
    _observeToken(newToken, 'refresh');
    _trace('refresh.committed');
    return newToken;
  }

  static Future<void> logout() async {
    _trace('credential.logout_started');
    _credentialEpoch++;
    final refresh = await _readStorage(AuthStorageSlot.refresh, 'logout', logPresent: true);
    await _deleteStorage(AuthStorageSlot.access, 'logout');
    await _deleteStorage(AuthStorageSlot.refresh, 'logout');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_loginMethodKey);
    _missingStorageProbed = true;
    _observeToken(null, 'logout');
    _trace('credential.logout_completed');
    if (refresh != null && refresh.isNotEmpty) {
      // 先本地退出，再尽力撤销服务器会话；网络不阻塞界面。
      unawaited(() async {
        try {
          await HttpUtil.post(
            Uri.parse('${ApiService.baseUrl}/auth/logout'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': refresh}),
          ).timeout(ApiService.postTimeout);
        } catch (_) {}
      }());
    }
  }

  /// 本地数据模式初始化 — 创建本地 guest 用户和基础数据。
  /// 不会覆盖已有云端 token。
  static Future<void> initLocalUser() async {
    final existing = await getToken(source: 'local_init');
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
    if (existing.isEmpty) {
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
    await listRepo.ensureInbox();
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

  static Future<void> _saveAuth(
    String token,
    User user, {
    String? refreshToken,
    String? loginMethod,
  }) async {
    if (!token.startsWith('local:') && _isJwtExpired(token)) {
      throw StateError('登录凭据无效，未保存登录状态');
    }
    final oldToken = await getToken(source: 'save.previous');
    final oldRefresh = await _readStorage(
      AuthStorageSlot.refresh, 'save.previous', logPresent: true,
    );
    _credentialEpoch++;
    try {
      if (refreshToken == null || refreshToken.isEmpty) {
        await _deleteStorage(AuthStorageSlot.refresh, 'save.no_refresh');
      } else {
        await _writeStorage(AuthStorageSlot.refresh, refreshToken, 'save');
      }
      await _writeStorage(AuthStorageSlot.access, token, 'save');
      // 只有读回确认为有效凭据，登录页面才能宣布成功。
      if (await _readStorage(
            AuthStorageSlot.access, 'save.verify', logPresent: true,
          ) != token ||
          await _readStorage(
            AuthStorageSlot.refresh, 'save.verify', logPresent: true,
          ) !=
              (refreshToken == null || refreshToken.isEmpty
                  ? null : refreshToken)) {
        throw StateError('登录凭据保存后无法读回');
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.setString(_userKey, json.encode(user.toJson()));
      if (loginMethod == null) {
        await prefs.remove(_loginMethodKey);
      } else {
        await prefs.setString(_loginMethodKey, loginMethod);
      }
      _missingStorageProbed = false;
      _observeToken(token, 'save');
      final method = token.startsWith('local:')
          ? 'local'
          : loginMethod == 'github'
              ? 'github'
              : loginMethod == 'password'
                  ? 'password'
                  : 'linked';
      _trace('credential.save_completed method=$method '
          'refresh=${refreshToken == null || refreshToken.isEmpty ? 'absent' : 'present'}');
    } catch (error) {
      _trace('credential.save_failed kind=${error.runtimeType}');
      // 写入失败恢复旧凭据；旧登录不得被失败的 GitHub 会话覆盖。
      if (oldToken == null) {
        await _deleteStorage(AuthStorageSlot.access, 'save.rollback');
      } else {
        await _writeStorage(AuthStorageSlot.access, oldToken, 'save.rollback');
      }
      if (oldRefresh == null) {
        await _deleteStorage(AuthStorageSlot.refresh, 'save.rollback');
      } else {
        await _writeStorage(AuthStorageSlot.refresh, oldRefresh, 'save.rollback');
      }
      rethrow;
    }
  }
}
