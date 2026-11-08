import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/repositories/habit_repository.dart';
import 'package:slowlight/services/cloud_api_service.dart';

// A cached empty history cannot establish that the cloud server deleted
// an exact log. The repository must use its dedicated authoritative read.
class _OfflineCloudHabitSource extends CloudApiService {
  int cachedReads = 0;
  int verifiedReads = 0;

  @override
  Future<Map<String, dynamic>> getHabitLogs(
      int habitId, {String? month}) async {
    cachedReads++;
    return {'logs': <Map<String, dynamic>>[]};
  }

  @override
  Future<Map<String, dynamic>> getHabitLogsForVerification(
      int habitId, {String? month}) async {
    verifiedReads++;
    throw StateError('server unavailable');
  }
}

void main() {
  test('X06 云端缓存为空也不能当作服务端撤销成功的证据', () async {
    final source = _OfflineCloudHabitSource();
    final repository = HabitRepository(dataSource: source);

    expect(await repository.logs(8), isEmpty);
    expect(source.cachedReads, 1);

    await expectLater(repository.logsForVerification(8), throwsStateError);
    expect(source.verifiedReads, 1);
    expect(source.cachedReads, 1);
  });
}
