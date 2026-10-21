import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/cloud_cache_db.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/services/data_mode_manager.dart';
import 'package:slowlight/services/sync_service.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late String dbPath;
  late String cloudDbPath;

  const cloudUserId = 42;
  final cloudUserJson = jsonEncode({
    'id': cloudUserId,
    'username': 'cloud_test',
    'email': 'cloud@example.com',
    'nickname': 'Cloud Test',
    'avatar': null,
    'created_at': '2026-08-21T00:00:00.000Z',
  });

  setUpAll(() async {
    final root = await useIsolatedTestDb('sync_service');
    dbPath = p.join(root, 'slowlight_offline.db');
    cloudDbPath = p.join(root, 'slowlight_cloud_cache_user_$cloudUserId.db');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CloudCacheDb().close();
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
    await databaseFactory.deleteDatabase(cloudDbPath);
    await DataModeManager().setLocal();
  });

  tearDown(() async {
    SyncService().dispose2();
    await CloudCacheDb().close();
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
    await databaseFactory.deleteDatabase(cloudDbPath);
  });

  Future<void> signInCloudUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', cloudUserJson);
  }

  test('Local Data Mode 禁止把普通 CRUD 放入 sync_queue', () async {
    final sync = SyncService();

    expect(
      () => sync.enqueue(
        entityType: 'tasks',
        entityLocalId: 1,
        operation: 'create',
      ),
      throwsA(isA<StateError>()),
    );

    final db = await LocalDb().database;
    final queue = await db.query('sync_queue');
    expect(queue, isEmpty);
  });

  test('Cloud Sync deviceId 会持久化到本地设置', () async {
    await signInCloudUser();
    await DataModeManager().setCloud();
    final sync = SyncService();
    await sync.init(startPeriodic: false);

    expect(sync.deviceId, isNotEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('slowlight_sync_device_id'), sync.deviceId);
  });

  test('Cloud Sync cache 与 Local Data 数据库物理隔离', () async {
    await signInCloudUser();
    await DataModeManager().setCloud();

    final cloudDb = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    await cloudDb.insert('lists', {
      'server_id': 1001,
      'name': '云端缓存清单',
      'created_at': now,
      'updated_at': now,
    });

    final localDb = await LocalDb().database;
    expect(await cloudDb.query('lists'), hasLength(1));
    expect(await localDb.query('lists'), isEmpty);
  });

  test('ConflictScreen 的“用服务端”明确解析为 remoteWins', () {
    expect(
      SyncConflictPolicy.requestedStrategy(keepLocal: false),
      ConflictStrategy.remoteWins,
    );
    expect(
      SyncConflictPolicy.requestedStrategy(keepLocal: true),
      ConflictStrategy.localWins,
    );
    expect(
      SyncConflictPolicy.requestedStrategy(
        strategy: ConflictStrategy.merge,
      ),
      ConflictStrategy.merge,
    );
  });


  Future<void> prepareCloud() async {
    await signInCloudUser();
    await DataModeManager().setCloud();
    await SyncService().init(startPeriodic: false);
  }

  Future<int> addQueuedUnsupportedOperation(Database db, {int retries = 0}) {
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('sync_queue', {
      'entity_type': 'unsupported_entity',
      'entity_local_id': 999,
      'operation': 'update',
      'retry_count': retries,
      'last_error': 'previous error',
      'created_at': now,
      'updated_at': now,
    });
  }

  test('失败重试与清理均不删除未同步记录', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    await addQueuedUnsupportedOperation(db, retries: 3);

    await SyncService().cleanupFailedItems();
    expect(await db.query('sync_queue'), hasLength(1));

    await SyncService().retryFailed();
    final queued = (await db.query('sync_queue')).single;
    expect(queued['retry_count'], 1);
    expect(SyncService().status, SyncStatusEnum.error);
    expect(SyncService().pendingCount, 1);
  });

  test('单条上传失败时 manualSync 返回 false 且保留队列', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    await addQueuedUnsupportedOperation(db);

    final result = await SyncService().manualSync();
    expect(result, isFalse);
    expect(SyncService().status, SyncStatusEnum.error);
    expect(SyncService().lastError, contains('unsupported_entity'));
    expect(SyncService().pendingCount, 1);
    expect(await db.query('sync_queue'), hasLength(1));
  });

  test('非任务冲突可查询且后台同步不覆盖冲突记录', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '冲突清单',
      'server_id': 301,
      'sync_status': 'conflict',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('sync_queue', {
      'entity_type': 'lists',
      'entity_local_id': listId,
      'entity_server_id': 301,
      'operation': 'update',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('habits', {
      'name': '冲突习惯',
      'server_id': 401,
      'sync_status': 'conflict',
      'created_at': now,
      'updated_at': now,
    });
    final conflicts = await SyncService().getAllConflicts();
    expect(conflicts.map((c) => c['_entity_type']),
        containsAll(<String>['lists', 'habits']));

    expect(await SyncService().manualSync(), isFalse);
    expect(SyncService().lastError, contains('待处理的冲突'));
    expect(await db.query('sync_queue'), hasLength(1));
    expect(
      (await db.query('lists', where: 'id = ?', whereArgs: [listId]))
          .single['sync_status'],
      'conflict',
    );
  });


  test('保留本地删除冲突时，重入队列仍然是 delete 而不是 update', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '测试清单', 'server_id': 22,
      'created_at': now, 'updated_at': now,
    });
    final taskId = await db.insert('tasks', {
      'list_id': listId,
      'server_id': 99,
      'title': '待删除',
      'created_at': now,
      'updated_at': now,
      'deleted_at': now,
      'sync_status': 'conflict',
    });
    await db.insert('sync_queue', {
      'entity_type': 'tasks',
      'entity_local_id': taskId,
      'entity_server_id': 99,
      'operation': 'delete',
      'created_at': now,
      'updated_at': now,
    });

    final resolved = await SyncService().resolveConflict(
      taskId, entityType: 'tasks', keepLocal: true,
    );
    expect(resolved, isTrue);
    final queue = await db.query('sync_queue');
    expect(queue, hasLength(1));
    expect(queue.single['operation'], 'delete');
    expect((await db.query('tasks', where: 'id = ?', whereArgs: [taskId]))
        .single['sync_status'], 'pending');
  });

  test('不支持 HabitLog 合并时保持原冲突内容不变', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final habitId = await db.insert('habits', {
      'server_id': 41,
      'name': '阅读',
      'created_at': now,
      'updated_at': now,
    });
    final logId = await db.insert('habit_logs', {
      'server_id': 42,
      'habit_id': habitId,
      'date': '2026-10-18',
      'note': '本地记录',
      'created_at': now,
      'sync_status': 'conflict',
    });

    final resolved = await SyncService().resolveConflict(
      logId,
      entityType: 'habit_logs',
      strategy: ConflictStrategy.merge,
      serverVersion: {
        'id': 42,
        'habit_id': 41,
        'date': '2026-10-18',
        'note': '云端记录',
      },
    );
    expect(resolved, isFalse);
    final row = (await db.query('habit_logs',
        where: 'id = ?', whereArgs: [logId])).single;
    expect(row['sync_status'], 'conflict');
    expect(row['note'], '本地记录');
  });

  test('保留既有 SyncService 公开能力', () {
    final sync = SyncService();
    expect(sync.detectConflict, isA<Function>());
    expect(sync.resolveConflict, isA<Function>());
    expect(sync.enqueue, isA<Function>());
    expect(sync.syncBatch, isA<Function>());
    expect(sync.retryFailed, isA<Function>());

    final op = SyncOperation(
      table: 'tasks',
      recordId: 1,
      action: 'update',
    );
    expect(op.table, 'tasks');
    expect(op.recordId, 1);
    expect(op.action, 'update');
  });

  test('新安装默认云端且写入选择，已有本地数据库保持本地', () async {
    final prefs = await SharedPreferences.getInstance();
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
    await prefs.remove('data_mode');
    DataModeManager().resetForTesting();

    await DataModeManager().load();
    expect(DataModeManager().isCloud, isTrue);
    expect(prefs.getString('data_mode'), 'cloud');

    // Simulate upgrading an old build which did not store the mode.
    await LocalDb().database;
    await DataModeManager().setLocal();
    await prefs.remove('data_mode');
    DataModeManager().resetForTesting();
    await DataModeManager().load();
    expect(DataModeManager().isLocal, isTrue);
    expect(prefs.getString('data_mode'), 'local');
  });

}
