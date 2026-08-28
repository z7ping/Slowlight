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
