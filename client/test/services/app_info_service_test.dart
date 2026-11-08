import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/app_info_service.dart';

void main() {
  test('服务端构建元数据允许缺失，不伪造版本与时间', () {
    const hash = '1234567890123456789012345678901234567890';
    final info = ServerVersionInfo.fromJson({
      'version': '0.2.1',
      'deployed_at': null,
      'commit_time': '2026-11-07T10:00:00Z',
      'commit_hash': hash,
      'built_at': '',
    });

    expect(info.version, '0.2.1');
    expect(info.deployedAt, isNull);
    expect(info.commitTime, '2026-11-07T10:00:00Z');
    expect(info.commitHash, hash);
    expect(info.builtAt, isNull);
    final missing = ServerVersionInfo.fromJson({'version': null});
    expect(missing.version, isNull);
    expect(missing.commitHash, isNull);
  });
}
