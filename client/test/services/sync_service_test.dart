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
}
