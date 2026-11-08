import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/api_service.dart';
import 'package:slowlight/services/app_secure_storage.dart';
import 'package:slowlight/services/auth_storage_diagnostics.dart';
import 'package:slowlight/services/github_oauth_pending.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => AuthStorageDiagnostics.debugTraceSink = null);

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

  test('清理 GitHub 授权暂存只删 pending，前后记录 Access 存在性', () async {
    const access = 'the-access-credential-must-remain-unchanged';
    const poll = 'the-oauth-poll-credential-must-remain-private';
    FlutterSecureStorage.setMockInitialValues({'auth_token': access});
    final events = <String>[];
    AuthStorageDiagnostics.debugTraceSink = events.add;
    final pending = GitHubOAuthPending(
      sessionId: 'pending-id', pollToken: poll,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      endpoint: ApiService.baseUrl,
    );

    await GitHubOAuthPending.save(pending);
    expect((await GitHubOAuthPending.load())?.pollToken, poll);
    await GitHubOAuthPending.clear(reason: 'login_saved');

    final storage = AppSecureStorage.instance;
    expect(await storage.read(key: 'auth_token'), access);
    expect(await storage.read(key: GitHubOAuthPending.storageKey), isNull);
    final text = events.join('\n');
    expect(text, contains(
      'action=read slot=access '
      'actor=oauth.pending.before_clear.login_saved status=present',
    ));
    expect(text, contains(
      'action=read slot=access '
      'actor=oauth.pending.after_clear.login_saved status=present',
    ));
    expect(text, contains(
      'action=delete slot=oauthPending '
      'actor=oauth.pending.clear.login_saved phase=done',
    ));
    expect(text, isNot(contains(access)));
    expect(text, isNot(contains(poll)));
    expect(text, isNot(contains('pending-id')));
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
