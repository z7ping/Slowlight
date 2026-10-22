import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_service.dart';

/// Android 待完成的 GitHub 会话，数据仅保存在系统安全存储中。
class GitHubOAuthPending {
  const GitHubOAuthPending({
    required this.sessionId,
    required this.pollToken,
    required this.expiresAt,
    required this.endpoint,
    this.flow = 'browser',
    this.userCode = '',
    this.verificationUri = '',
  });

  static const storageKey = 'github_oauth_pending';
  static const secureStorage = FlutterSecureStorage();

  final String sessionId;
  final String pollToken;
  final DateTime expiresAt;
  final String endpoint;
  final String flow;
  final String userCode;
  final String verificationUri;

  bool get isValid =>
      sessionId.isNotEmpty &&
      pollToken.isNotEmpty &&
      endpoint == ApiService.baseUrl &&
      expiresAt.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'poll_token': pollToken,
        'expires_at': expiresAt.toUtc().millisecondsSinceEpoch,
        'endpoint': endpoint,
        'flow': flow,
        'user_code': userCode,
        'verification_uri': verificationUri,
      };

  static GitHubOAuthPending? fromJson(Object? data) {
    if (data is! Map<String, dynamic>) return null;
    final sessionId = data['session_id'];
    final pollToken = data['poll_token'];
    final expiresAt = data['expires_at'];
    final endpoint = data['endpoint'];
    if (sessionId is! String || pollToken is! String ||
        expiresAt is! int || endpoint is! String) return null;
    final pending = GitHubOAuthPending(
      sessionId: sessionId,
      pollToken: pollToken,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt, isUtc: true),
      endpoint: endpoint,
      flow: data['flow'] is String ? data['flow'] as String : 'browser',
      userCode: data['user_code'] is String ? data['user_code'] as String : '',
      verificationUri: data['verification_uri'] is String
          ? data['verification_uri'] as String
          : '',
    );
    return pending.isValid ? pending : null;
  }

  static Future<void> save(GitHubOAuthPending pending) =>
      secureStorage.write(key: storageKey, value: jsonEncode(pending.toJson()));

  static Future<GitHubOAuthPending?> load() async {
    final raw = await secureStorage.read(key: storageKey);
    if (raw == null) return null;
    try {
      final pending = fromJson(jsonDecode(raw));
      if (pending != null) return pending;
    } on FormatException {
      // 忽略无法解析的历史记录。
    }
    await clear();
    return null;
  }

  static Future<void> clear() => secureStorage.delete(key: storageKey);
}
