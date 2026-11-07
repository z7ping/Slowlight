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
  test('P05 V3 达标后仍能继续记录，重试幂等且完整历史不截断', () async {
    final repo = LocalHabitRepository();
    const rule = <String, dynamic>{
      'version': 1,
      'kind': 'goal',
      'unit': 'week',
      'every': 1,
      'anchor_date': '2026-01-01',
      'anchor_time': '08:00',
      'target_count': 1,
      'same_day_multiple': true,
      'reminder_mode': 'off',
      'reminder_time': '09:00',
    };
    final habit = await repo.create(
      name: '每周真实记录', frequency: 'custom',
      scheduleRule: rule, allowMultiplePerDay: true,
    );
    final id = habit['id'] as int;
    final first = await repo.checkIn(id,
        occurrenceKey: 'event:p05-local-one',
        clientKey: 'p05-local-stable-key-one');
    final replay = await repo.checkIn(id,
        occurrenceKey: 'event:p05-local-one',
        clientKey: 'p05-local-stable-key-one');
    expect(replay['already_checked'], isTrue);
    expect((replay['log'] as Map)['id'], (first['log'] as Map)['id']);
    await repo.checkIn(id,
        occurrenceKey: 'event:p05-local-two',
        clientKey: 'p05-local-stable-key-two');
    final loaded = (await repo.getAll()).single;
    expect(loaded['period_count'], 2);
    expect(loaded['period_target'], 1);
    expect(loaded['can_check_in'], isTrue);
    expect((await repo.getLogs(id))['logs'], hasLength(2));

    // Existing getLogs without a month is the actual all-history source,
    // not a UI approximation based on the most recent 3 / 100 entries.
    final older = await repo.create(
      name: '多条历史', allowMultiplePerDay: true,
    );
    final oldId = older['id'] as int;
    for (var index = 0; index < 105; index++) {
      await repo.checkIn(oldId, clientKey: 'p05-history-$index');
    }
    final history = (await repo.getLogs(oldId))['logs'] as List;
    expect(history, hasLength(105));
    final ids = history.map((entry) => (entry as Map)['id'] as int).toList();
    expect(ids.first, greaterThan(ids.last));
  });

}
