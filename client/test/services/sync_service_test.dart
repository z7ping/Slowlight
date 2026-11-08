import 'dart:async';
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
    SyncService().debugRemoteRead = null;
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
    expect(queued['retry_count'], 3);
    expect(queued['last_error'], 'previous error');
    expect(SyncService().status, SyncStatusEnum.error);
    expect(SyncService().pendingCount, 1);
  });

  test('P1-4 旧失败重试入口不得清空超时回执、重放未知创建', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('sync_queue', {
      'entity_type': 'habits', 'entity_local_id': 994,
      'operation': 'create', 'entity_server_id': null,
      'retry_count': 3, 'last_error': 'TimeoutException: 创建回执未知',
      'created_at': now, 'updated_at': now,
    });
    await SyncService().retryFailed();
    final row = (await db.query('sync_queue',
        where: 'id = ?', whereArgs: [id])).single;
    expect(row['retry_count'], 3);
    expect(row['last_error'], 'TimeoutException: 创建回执未知');
    expect(row['operation'], 'create');
    expect(SyncService().status, SyncStatusEnum.error);
    expect(SyncService().lastError, contains('不自动重发'));
    expect(SyncService().pendingCount, 1);
  });

  test('X09 失败范围读取保留完整原错误，不重播、不丢已入队记录', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final longError = '完整原始异常：' + List.filled(80, 'network-reset').join('|');
    await db.insert('sync_queue', {
      'entity_type': 'tasks', 'entity_local_id': 701,
      'operation': 'update', 'retry_count': 2,
      'last_error': longError,
      'created_at': now, 'updated_at': now,
    });
    await db.insert('sync_queue', {
      'entity_type': 'habits', 'entity_local_id': 702,
      'operation': 'create', 'retry_count': 1,
      'last_error': 'timeout: 尚待核对远端是否已提交',
      'created_at': now, 'updated_at': now,
    });
    await db.insert('sync_queue', {
      'entity_type': 'lists', 'entity_local_id': 703,
      'operation': 'update', 'retry_count': 0,
      'last_error': '',
      'created_at': now, 'updated_at': now,
    });
    final before = await db.query('sync_queue');
    final failures = await SyncService().getPendingFailures();
    expect(failures, hasLength(2));
    expect(failures.map((item) => item.entityLocalId),
        containsAll(<int>[701, 702]));
    final error = failures.singleWhere((item) => item.entityLocalId == 701);
    expect(error.entityType, 'tasks');
    expect(error.operation, 'update');
    expect(error.retryCount, 2);
    expect(error.error, longError);
    expect(await db.query('sync_queue'), before);
    expect(SyncService().status, isNot(SyncStatusEnum.syncing));
  });

  test('X09 部分同步失败返回准确的本轮尝试/失败数量', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    await addQueuedUnsupportedOperation(db);
    await db.insert('sync_queue', {
      'entity_type': 'another_unsupported_entity',
      'entity_local_id': 998,
      'operation': 'update',
      'retry_count': 0,
      'last_error': '',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    expect(await SyncService().manualSync(), isFalse);
    expect(SyncService().lastError, contains('本轮处理 2 项，其中 2 项未完成'));
    expect((await SyncService().getPendingFailures()).length, 2);
    expect((await db.query('sync_queue')).length, 2);
  });

  test('X09 远端已写入的旧失败队列被确认后精确清理', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '云端已写入', 'icon': '📋', 'color': '#112233',
      'server_id': 120, 'is_inbox': 0, 'sync_status': 'conflict',
      'last_modified': 'revision-1',
      'created_at': now, 'updated_at': now,
    });
    await db.insert('sync_queue', {
      'entity_type': 'lists', 'entity_local_id': listId,
      'entity_server_id': 120, 'operation': 'update',
      'retry_count': 1, 'last_error': 'TimeoutException: no receipt',
      'created_at': now, 'updated_at': now,
    });
    var reads = 0;
    SyncService().debugRemoteRead = (database, table, id, local) async {
      reads++;
      expect(table, 'lists');
      expect(id, 120);
      return {
        'name': '云端已写入', 'icon': '📋',
        'color': '#112233', 'is_inbox': false,
      };
    };
    final result = await SyncService().reconcileFailedWrites();
    expect(result.verified, 1);
    expect(result.conflicts, 0);
    expect(result.unknown, 0);
    expect(reads, 1);
    expect(await db.query('sync_queue'), isEmpty);
    expect((await db.query('lists', where: 'id = ?',
      whereArgs: [listId])).single['sync_status'], 'synced');
  });

  test('X09 远端不一致时保留原始失败请求交给冲突界面', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '本地计划', 'icon': '📋',
      'color': '#112233', 'server_id': 121, 'is_inbox': 0,
      'sync_status': 'pending',
      'last_modified': 'revision-2',
      'created_at': now, 'updated_at': now,
    });
    await db.insert('sync_queue', {
      'entity_type': 'lists', 'entity_local_id': listId,
      'entity_server_id': 121, 'operation': 'update',
      'retry_count': 1, 'last_error': 'connection reset',
      'created_at': now, 'updated_at': now,
    });
    SyncService().debugRemoteRead = (_, __, ___, ____) async => {
      'name': '另一设备的版本', 'icon': '📋',
      'color': '#112233', 'is_inbox': false,
    };
    final result = await SyncService().reconcileFailedWrites();
    expect(result.conflicts, 1);
    expect(result.verified, 0);
    expect(await db.query('sync_queue'), hasLength(1));
    expect((await db.query('lists', where: 'id = ?',
      whereArgs: [listId])).single['sync_status'], 'conflict');
  });

  test('X09 远端读取期间本地再次更改不会丢掉新决定', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '原本地名', 'icon': '📋',
      'color': '#112233', 'server_id': 122, 'is_inbox': 0,
      'sync_status': 'pending',
      'last_modified': 'before',
      'created_at': now, 'updated_at': now,
    });
    await db.insert('sync_queue', {
      'entity_type': 'lists', 'entity_local_id': listId,
      'entity_server_id': 122, 'operation': 'update',
      'retry_count': 1, 'last_error': 'timeout',
      'created_at': now, 'updated_at': now,
    });
    SyncService().debugRemoteRead = (database, _, __, ___) async {
      await database.update('lists',
        {'name': '新本地草稿', 'last_modified': 'after'},
        where: 'id = ?', whereArgs: [listId]);
      return {'name': '原本地名', 'icon': '📋',
        'color': '#112233', 'is_inbox': false};
    };
    final result = await SyncService().reconcileFailedWrites();
    expect(result.verified, 0);
    expect(result.unknown, 1);
    expect(await db.query('sync_queue'), hasLength(1));
    expect((await db.query('lists', where: 'id = ?',
      whereArgs: [listId])).single['name'], '新本地草稿');
  });

  test('X09 核对中切换账号不得更新原账户队列', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '原账号', 'icon': '📋',
      'color': '#112233', 'server_id': 144,
      'sync_status': 'pending', 'is_inbox': 0,
      'created_at': now, 'updated_at': now,
      'last_modified': 'original',
    });
    await db.insert('sync_queue', {
      'entity_type': 'lists', 'entity_local_id': listId,
      'entity_server_id': 144, 'operation': 'update',
      'retry_count': 1, 'last_error': 'timeout',
      'created_at': now, 'updated_at': now,
    });
    SyncService().debugRemoteRead = (_, __, ___, ____) async {
      final prefs = await SharedPreferences.getInstance();
      final user = Map<String, dynamic>.from(
        jsonDecode(cloudUserJson) as Map,
      )..['id'] = 77;
      await prefs.setString('user_data', jsonEncode(user));
      return {'name': '原账号', 'icon': '📋',
        'color': '#112233', 'is_inbox': false};
    };
    await expectLater(
      SyncService().reconcileFailedWrites(), throwsStateError,
    );
    expect(await db.query('sync_queue'), hasLength(1));
    expect((await db.query('lists', where: 'id = ?',
      whereArgs: [listId])).single['sync_status'], 'pending');
  });

  test('X09 远端核对期间不允许后台/手动同步重放同一队列', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '等待核对', 'server_id': 199,
      'icon': '📋', 'color': '#112233', 'is_inbox': 0,
      'sync_status': 'conflict', 'last_modified': 'v1',
      'created_at': now, 'updated_at': now,
    });
    await db.insert('sync_queue', {
      'entity_type': 'lists', 'entity_local_id': listId,
      'entity_server_id': 199, 'operation': 'update',
      'retry_count': 1, 'last_error': 'timeout',
      'created_at': now, 'updated_at': now,
    });
    final remoteRead = Completer<Map<String, dynamic>?>();
    final entered = Completer<void>();
    SyncService().debugRemoteRead = (_, __, ___, ____) async {
      entered.complete();
      return remoteRead.future;
    };
    final pending = SyncService().reconcileFailedWrites();
    await entered.future;
    expect(await SyncService().manualSync(), isFalse);
    await SyncService().syncBatch();
    await SyncService().retryFailed();
    expect(await db.query('sync_queue'), hasLength(1));
    remoteRead.complete({
      'name': '等待核对', 'icon': '📋',
      'color': '#112233', 'is_inbox': false,
    });
    final result = await pending;
    expect(result.verified, 1);
    expect(await db.query('sync_queue'), isEmpty);
  });

  test('X09 历史 SocketException 回执未知不能被后台盲重发', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('lists', {
      'name': '已提交与否未知', 'server_id': 204,
      'sync_status': 'pending', 'created_at': now, 'updated_at': now,
    });
    await db.insert('sync_queue', {
      'entity_type': 'lists', 'entity_local_id': id,
      'entity_server_id': 204, 'operation': 'update',
      'retry_count': 1,
      'last_error': 'SocketException: Connection refused',
      'created_at': now, 'updated_at': now,
    });
    expect(await SyncService().manualSync(), isFalse);
    expect(await db.query('sync_queue'), hasLength(1));
    expect((await db.query('lists', where: 'id = ?',
      whereArgs: [id])).single['sync_status'], 'conflict');
  });

  test('X09 历史 timeout 回执先隔离，不因后台周期重放', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '禁止盲重发', 'server_id': 123,
      'sync_status': 'pending',
      'created_at': now, 'updated_at': now,
    });
    await db.insert('sync_queue', {
      'entity_type': 'lists', 'entity_local_id': listId,
      'entity_server_id': 123, 'operation': 'update',
      'retry_count': 1, 'last_error': 'TimeoutException: response unknown',
      'created_at': now, 'updated_at': now,
    });
    expect(await SyncService().manualSync(), isFalse);
    expect((await db.query('lists', where: 'id = ?',
      whereArgs: [listId])).single['sync_status'], 'conflict');
    expect(await db.query('sync_queue'), hasLength(1));
  });

  test('X09 未分配远端 ID 的 create 保留未知，不通过普通读取假确认', () async {
    await prepareCloud();
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('sync_queue', {
      'entity_type': 'lists', 'entity_local_id': 300,
      'operation': 'create', 'retry_count': 1,
      'last_error': 'timeout',
      'created_at': now, 'updated_at': now,
    });
    final result = await SyncService().reconcileFailedWrites();
    expect(result.unknown, 1);
    expect(result.verified, 0);
    expect(await db.query('sync_queue'), hasLength(1));
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
