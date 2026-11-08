import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/auth_storage_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => AuthStorageDiagnostics.debugTraceSink = null);

  test('每次安全存储写入、读取与清理都能关联操作号，且不记录凭据', () async {
    const storage = FlutterSecureStorage();
    const secret = 'private-access-credential-never-export';
    final events = <String>[];
    AuthStorageDiagnostics.debugTraceSink = events.add;

    await AuthStorageDiagnostics.write(
      storage, slot: AuthStorageSlot.access, value: secret,
      actor: 'save',
    );
    expect(
      await AuthStorageDiagnostics.read(
        storage, slot: AuthStorageSlot.access,
        actor: 'sidebar', logPresent: true,
      ),
      secret,
    );
    await AuthStorageDiagnostics.delete(
      storage, slot: AuthStorageSlot.access, actor: 'logout',
    );
    expect(
      await AuthStorageDiagnostics.read(
        storage, slot: AuthStorageSlot.access,
        actor: 'auth_check', logPresent: true,
      ),
      isNull,
    );

    final recorded = events.join('\n');
    expect(recorded, contains('process_started trace=auth_storage_v1'));
    expect(recorded, contains('action=write slot=access actor=save phase=start'));
    expect(recorded, contains('action=write slot=access actor=save phase=done'));
    expect(recorded, contains('action=read slot=access actor=sidebar status=present'));
    expect(recorded, contains('action=delete slot=access actor=logout phase=done'));
    expect(recorded, contains('action=read slot=access actor=auth_check status=missing'));
    expect(recorded, isNot(contains(secret)));
    expect(recorded, isNot(contains('Bearer ')));

    final writes = events.where((e) => e.contains('action=write slot=access')).toList();
    expect(writes, hasLength(2));
    final startId = RegExp(r'op=(\d+)').firstMatch(writes.first)?.group(1);
    final doneId = RegExp(r'op=(\d+)').firstMatch(writes.last)?.group(1);
    expect(startId, isNotNull);
    expect(startId, doneId);
  });

  test('没有请求外部网络，checkpoint 只读取存在性且不修改身份', () async {
    const storage = FlutterSecureStorage();
    const token = 'another-secret-that-must-not-be-logged';
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': token,
    });
    final events = <String>[];
    AuthStorageDiagnostics.debugTraceSink = events.add;

    await AuthStorageDiagnostics.checkpoint(
      storage, slot: AuthStorageSlot.access, actor: 'oauth.pending.before_clear',
    );
    await AuthStorageDiagnostics.checkpoint(
      storage, slot: AuthStorageSlot.access, actor: 'oauth.pending.after_clear',
    );
    expect(await storage.read(key: 'auth_token'), token);
    expect(events.join('\n'), contains('actor=oauth.pending.after_clear status=present'));
    expect(events.join('\n'), isNot(contains(token)));
  });
}
