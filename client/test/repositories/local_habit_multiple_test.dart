import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/repositories/local_habit_repository.dart';
import '../helpers/isolated_test_db.dart';

void main() {
  setUpAll(() async {
    await useIsolatedTestDb('local_habit_multi');
  });
  setUp(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(LocalDb.debugDatabasePathOverride!);
  });
  tearDown(() async {
    await LocalDb().close();
  });
  test('同日多条累计、按记录撤销、默认旧习惯单日一次', () async {
    final repo = LocalHabitRepository();
    final habit = await repo.create(
      name: '喝水', recordType: 'count', recordUnit: '杯',
      allowMultiplePerDay: true,
      goalPeriod: 'day', goalMetric: 'count', goalValue: 8,
    );
    final id = habit['id'] as int;
    final first = await repo.checkIn(id, countValue: 1);
    await repo.checkIn(id, countValue: 2);
    expect((await repo.getLogs(id))['logs'], hasLength(2));
    expect((await repo.getAll()).single['goal_progress'], 3);
    await repo.deleteLog(id, (first['log'] as Map)['id'] as int);
    expect((await repo.getAll()).single['goal_progress'], 2);
    final legacy = await repo.create(name: '阅读');
    await repo.checkIn(legacy['id'] as int);
    await repo.checkIn(legacy['id'] as int);
    expect((await repo.getLogs(legacy['id'] as int))['logs'], hasLength(1));
  });
}
