import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/api_service.dart';
import 'package:slowlight/services/github_oauth_pending.dart';

void main() {
  test('有效的 Android 授权会话可序列化并恢复', () {
    final original = GitHubOAuthPending(
      sessionId: 'session-id',
      pollToken: 'poll-secret',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      endpoint: ApiService.baseUrl,
    );
    final restored = GitHubOAuthPending.fromJson(original.toJson());
    expect(restored, isNotNull);
    expect(restored!.sessionId, original.sessionId);
    expect(restored.pollToken, original.pollToken);
  });

  test('已过期的授权会话不能恢复', () {
    final expired = GitHubOAuthPending(
      sessionId: 'expired',
      pollToken: 'expired-token',
      expiresAt: DateTime.now().subtract(const Duration(seconds: 5)),
      endpoint: ApiService.baseUrl,
    );
    expect(GitHubOAuthPending.fromJson(expired.toJson()), isNull);
  });

  test('其他云端地址的授权会话不能恢复', () {
    final mismatched = GitHubOAuthPending(
      sessionId: 'other-server',
      pollToken: 'token',
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      endpoint: 'https://another.example/api',
    );
    expect(GitHubOAuthPending.fromJson(mismatched.toJson()), isNull);
  });

  test('残缺或字段类型错误的授权会话不能恢复', () {
    expect(GitHubOAuthPending.fromJson({'session_id': 'id'}), isNull);
    expect(GitHubOAuthPending.fromJson('invalid'), isNull);
  });
  test('设备码会话可恢复但必须使用 GitHub HTTPS 验证页', () {
    final pending = GitHubOAuthPending(
      sessionId: 'device-session',
      pollToken: 'secret-poll',
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      endpoint: ApiService.baseUrl,
      flow: 'device',
      userCode: 'ABCD-1234',
      verificationUri: 'https://github.com/login/device',
    );
    final restored = GitHubOAuthPending.fromJson(pending.toJson());
    expect(restored?.flow, 'device');
    expect(restored?.userCode, 'ABCD-1234');
    final bad = {...pending.toJson(), 'verification_uri': 'https://evil.example/steal'};
    expect(GitHubOAuthPending.fromJson(bad), isNull);
  });

  test('账号绑定恢复必须记录且匹配用户标识', () {
    final pending = GitHubOAuthPending(
      sessionId: 'account-link',
      pollToken: 'poll',
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      endpoint: ApiService.baseUrl,
      linkExisting: true,
      targetUserId: 42,
    );
    expect(GitHubOAuthPending.fromJson(pending.toJson())?.targetUserId, 42);
    expect(GitHubOAuthPending.fromJson({...pending.toJson(), 'target_user_id': 0}), isNull);
  });

}
