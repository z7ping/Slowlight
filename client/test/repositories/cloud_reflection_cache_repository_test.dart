import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/cloud_cache_db.dart';
import 'package:slowlight/models/reflection_entry.dart';
import 'package:slowlight/repositories/cloud_reflection_cache_repository.dart';
import 'package:slowlight/services/cloud_sync_coordinator.dart';
import 'package:slowlight/services/data_mode_manager.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late String cloudDbPath;

  const userId = 42;
  final userJson = jsonEncode({
    'id': userId,
    'username': 'reflection_test',
    'email': 'reflection@example.com',
    'nickname': 'Reflection Test',
    'avatar': null,
    'created_at': '2026-08-21T00:00:00.000Z',
  });

  setUpAll(() async {
    final root = await useIsolatedTestDb('reflection_cache');
    cloudDbPath = p.join(root, 'slowlight_cloud_cache_user_$userId.db');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'user_data': userJson});
    CloudSyncCoordinator().stop();
    await CloudCacheDb().close();
    await databaseFactory.deleteDatabase(cloudDbPath);
    await DataModeManager().setCloud();
  });

  tearDown(() async {
    CloudSyncCoordinator().stop();
    await CloudCacheDb().close();
    await databaseFactory.deleteDatabase(cloudDbPath);
  });

  test('离线 Reflection 先落 Cloud Cache 并记录 create intent', () async {
    final repo = CloudReflectionCacheRepository();
    final created = await repo.createPending(
      content: '今天注意力很散',
      entryType: 'observation',
      dimensionKey: 'cognition',
      context: const {'source': 'today'},
    );

    expect(created.id, lessThan(0));
    expect(created.entryType, 'observation');

    final db = await CloudCacheDb().database;
    final rows = await db.query('reflections');
    expect(rows, hasLength(1));
    expect(rows.single['sync_status'], 'pending');
    expect(rows.single['content'], '今天注意力很散');

    final intents = await db.query('sync_intents');
    expect(intents, hasLength(1));
    expect(intents.single['entity_type'], 'reflections');
    expect(intents.single['intent'], 'create');
  });

  test('X07 离线观察补交保留最初云端请求的幂等标识', () async {
    const requestId = 'reflection:0123456789abcdef0123456789abcdef';
    final repo = CloudReflectionCacheRepository();
    await repo.createPending(
      content: '响应丢失后待核对的观察',
      entryType: 'observation',
      tagIds: const [31, 32],
      context: const {'source': 'today'},
      clientRequestId: requestId,
    );

    final db = await CloudCacheDb().database;
    final intent = (await db.query('sync_intents')).single;
    final value = jsonDecode(intent['value'] as String) as Map<String, dynamic>;
    expect(value['client_request_id'], requestId);
    expect(value['tag_ids'], [31, 32]);
    expect((await db.query('reflections')).single['content'], '响应丢失后待核对的观察');
  });

  test('P08 云缓存整月超过 100 条仍可读取，pending 按账号隔离', () async {
    final repo = CloudReflectionCacheRepository();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    final inside = DateTime(now.year, now.month, 2, 13);
    final before = start.subtract(const Duration(days: 1));
    await repo.cacheRemote([
      for (var id = 1; id <= 110; id++)
        ReflectionEntry(
          id: id, entryType: 'observation', content: '月内观察$id',
          createdAt: inside,
        ),
      ReflectionEntry(
        id: 999, entryType: 'observation',
        content: '上月观察', createdAt: before,
      ),
    ]);
    final pending = await repo.createPending(
      content: '未同步的当月观察', entryType: 'observation',
    );
    final full = await repo.month(start, end);
    final pendingOnly = await repo.month(start, end, pendingOnly: true);
    expect(full, hasLength(111));
    expect(full.map((item) => item.id), contains(pending.id));
    expect(full.map((item) => item.id), isNot(contains(999)));
    expect(pendingOnly.map((item) => item.id), [pending.id]);
  });

  test('P09 Cloud 历史关键词命中早期记录、字面通配符与待同步', () async {
    final repo = CloudReflectionCacheRepository();
    final old = DateTime(2024, 1, 1, 9);
    await repo.cacheRemote([
      ReflectionEntry(
        id: 701, entryType: 'observation',
        content: '旧记录 包含100%原样', createdAt: old,
      ),
      ReflectionEntry(
        id: 702, entryType: 'observation',
        content: '旧记录 包含100x原样', createdAt: old,
      ),
      ReflectionEntry(
        id: 703, entryType: 'observation',
        content: '旧记录 a_b', createdAt: old,
      ),
      ReflectionEntry(
        id: 704, entryType: 'observation',
        content: '旧记录 aXb', createdAt: old,
      ),
    ]);
    final pending = await repo.createPending(
      content: '未同步的历史检索记录', entryType: 'observation',
    );
    final percent = await repo.searchContent('100%');
    expect(percent.map((r) => r.id), [701]);
    final underscore = await repo.searchContent('a_b');
    expect(underscore.map((r) => r.id), [703]);
    final pendingOnly = await repo.searchContent(
      '检索记录', pendingOnly: true,
    );
    expect(pendingOnly.map((r) => r.id), [pending.id]);
  });

  test('recent 同时保留服务端 Reflection 与尚未补交的本地 Reflection', () async {
    final repo = CloudReflectionCacheRepository();
    final pending = await repo.createPending(
      content: '离线解释',
      entryType: 'reflection',
      context: const {},
    );
    await repo.cacheRemote([
      ReflectionEntry(
        id: 701,
        entryType: 'reflection',
        content: '服务端解释',
        createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    ]);

    final values = await repo.recent(limit: 20);
    expect(values.map((value) => value.id), containsAll([pending.id, 701]));
    expect(values.map((value) => value.content),
        containsAll(['离线解释', '服务端解释']));
  });

  test('补交成功后把负临时 id 收敛为 server id 并清除 intent', () async {
    final repo = CloudReflectionCacheRepository();
    final pending = await repo.createPending(
      content: '待补交',
      entryType: 'reflection',
      questionId: 'q-1',
      context: const {'answer': true},
    );
    final localId = -pending.id;
    final db = await CloudCacheDb().database;

    await repo.markCreateSynced(
      db,
      localId,
      ReflectionEntry(
        id: 801,
        entryType: 'reflection',
        questionId: 'q-1',
        content: '待补交',
        context: const {'answer': true},
        createdAt: DateTime.now(),
      ),
    );

    final values = await repo.recent(limit: 20);
    expect(values, hasLength(1));
    expect(values.single.id, 801);
    expect(await db.query('sync_intents'), isEmpty);
    expect((await db.query('reflections')).single['sync_status'], 'synced');
  });

  test('独立 Reflection intent 会立即计入待同步状态', () async {
    final repo = CloudReflectionCacheRepository();
    await repo.createPending(
      content: '离线待同步',
      entryType: 'reflection',
      context: const {},
    );

    final coordinator = CloudSyncCoordinator();
    await coordinator.refreshStandalonePendingCount();

    expect(coordinator.standalonePendingCount.value, 1);
  });

  test('已有普通 queue 屏障的 intent 不重复计数', () async {
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('sync_intents', {
      'entity_type': 'tasks',
      'entity_local_id': 99,
      'intent': 'completion',
      'value': '1',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('sync_queue', {
      'entity_type': 'tasks',
      'entity_local_id': 99,
      'entity_server_id': 501,
      'operation': 'update',
      'created_at': now,
      'updated_at': now,
    });

    final coordinator = CloudSyncCoordinator();
    await coordinator.refreshStandalonePendingCount();

    expect(coordinator.standalonePendingCount.value, 0);
  });
}
