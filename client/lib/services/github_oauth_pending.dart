import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_service.dart';
import 'auth_storage_diagnostics.dart';

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
    this.authorizationUrl = '',
    this.linkExisting = false,
    this.targetUserId = 0,
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
  final String authorizationUrl;
  final bool linkExisting;
  final int targetUserId;

  bool get isValid =>
      sessionId.isNotEmpty &&
      pollToken.isNotEmpty &&
      endpoint == ApiService.baseUrl &&
      expiresAt.isAfter(DateTime.now()) &&
      (!linkExisting || targetUserId > 0) &&
      (flow == 'browser' ||
          (flow == 'device' &&
              userCode.isNotEmpty &&
              Uri.tryParse(verificationUri)?.scheme == 'https' &&
              Uri.tryParse(verificationUri)?.host == 'github.com'));

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'poll_token': pollToken,
        'expires_at': expiresAt.toUtc().millisecondsSinceEpoch,
        'endpoint': endpoint,
        'flow': flow,
        'user_code': userCode,
        'verification_uri': verificationUri,
        'authorization_url': authorizationUrl,
        'link_existing': linkExisting,
        'target_user_id': targetUserId,
      };

  static GitHubOAuthPending? fromJson(Object? data) {
    if (data is! Map<String, dynamic>) return null;
    final sessionId = data['session_id'];
    final pollToken = data['poll_token'];
    final expiresAt = data['expires_at'];
    final endpoint = data['endpoint'];
    if (sessionId is! String ||
        pollToken is! String ||
        expiresAt is! int ||
        endpoint is! String) {
      return null;
    }
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
      authorizationUrl: data['authorization_url'] is String
          ? data['authorization_url'] as String
          : '',
      linkExisting: data['link_existing'] == true,
      targetUserId:
          data['target_user_id'] is int ? data['target_user_id'] as int : 0,
    );
    return pending.isValid ? pending : null;
  }

  static Future<void> save(GitHubOAuthPending pending) =>
      AuthStorageDiagnostics.write(
        secureStorage,
        slot: AuthStorageSlot.oauthPending,
        value: jsonEncode(pending.toJson()),
        actor: 'oauth.pending.save',
      );

  static Future<GitHubOAuthPending?> load() async {
    final raw = await AuthStorageDiagnostics.read(
      secureStorage,
      slot: AuthStorageSlot.oauthPending,
      actor: 'oauth.pending.load',
      logPresent: true,
    );
    if (raw == null) return null;
    try {
      final pending = fromJson(jsonDecode(raw));
      if (pending != null) return pending;
    } on FormatException {
      // 忽略无法解析的历史记录。
    }
    await clear(reason: 'invalid_pending');
    return null;
  }

  /// The two read-only access checkpoints show whether clearing the OAuth
  /// *pending* key unexpectedly affects the existing login credential.
  /// They never restore, copy or log an access token.
  static Future<void> clear({String reason = 'unspecified'}) async {
    await AuthStorageDiagnostics.checkpoint(
      secureStorage,
      slot: AuthStorageSlot.access,
      actor: 'oauth.pending.before_clear.$reason',
    );
    try {
      await AuthStorageDiagnostics.delete(
        secureStorage,
        slot: AuthStorageSlot.oauthPending,
        actor: 'oauth.pending.clear.$reason',
      );
    } finally {
      await AuthStorageDiagnostics.checkpoint(
        secureStorage,
        slot: AuthStorageSlot.access,
        actor: 'oauth.pending.after_clear.$reason',
      );
    }
  }
}
