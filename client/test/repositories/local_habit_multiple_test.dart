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
  test('P05 Local 历史目标版本只追加，不倒填旧记录', () async {
    final repo = LocalHabitRepository();
    final created = await repo.create(
      name: '目标修订', goalPeriod: 'week', goalValue: 3,
    );
    final id = created['id'] as int;
    List history(Map<String, dynamic> row) => row['goal_history'] as List;
    expect(history(created), hasLength(1));
    expect((history(created).first as Map)['goal_value'], 3);
    final cosmetic = await repo.update(id, name: '重命名');
    expect(history(cosmetic), hasLength(1));
    final revised = await repo.update(id, goalValue: 5);
    expect(history(revised), hasLength(2));
    expect((history(revised).first as Map)['goal_value'], 3);
    expect((history(revised).last as Map)['goal_value'], 5);
    final replay = await repo.update(id, goalValue: 5);
    expect(history(replay), hasLength(2));
    final db = await LocalDb().database;
    final legacyId = await db.insert('habits', {
      'name': '旧习惯', 'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final legacy = await repo.update(legacyId, goalValue: 4);
    expect(history(legacy), hasLength(1));
    expect((history(legacy).first as Map)['goal_value'], 4);
    await LocalDb().close();
    expect(history((await repo.getById(id))!), hasLength(2));
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
  test('P05 Local month filter returns real history and rejects wildcard', () async {
    final repo = LocalHabitRepository();
    final habit = await repo.create(name: '分月记录');
    final id = habit['id'] as int;
    final now = DateTime.now();
    final month = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}';
    await repo.checkIn(id);
    expect((await repo.getLogs(id))['logs'], hasLength(1));
    expect((await repo.getLogs(id, month: month))['logs'], hasLength(1));
    await expectLater(repo.getLogs(id, month: '$month%'),
        throwsFormatException);
    await expectLater(repo.getLogs(id, month: ''),
        throwsFormatException);
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
