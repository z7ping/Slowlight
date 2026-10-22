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
}
