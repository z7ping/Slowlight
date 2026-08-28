import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/services/sync_incremental_pull.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late String dbPath;

  setUpAll(() async {
    dbPath = p.join(
      await useIsolatedTestDb('sync_incremental_pull'),
      'slowlight_offline.db',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });

  tearDown(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });

  Future<int> insertList(Database db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('lists', {
      'server_id': 11,
      'name': 'Inbox',
      'created_at': now,
      'updated_at': now,
      'sync_status': 'synced',
    });
  }

  test('synced 远端 task tombstone 会软删除本地缓存并推进游标', () async {
    final db = await LocalDb().database;
    final listId = await insertList(db);
    final now = DateTime.now().toUtc().toIso8601String();
    final taskId = await db.insert('tasks', {
      'server_id': 101,
      'list_id': listId,
      'title': 'remote deleted',
      'created_at': now,
      'updated_at': now,
      'sync_status': 'synced',
    });

    await SyncIncrementalPull().applyChanges(db, {
      'server_time': '2026-08-21T00:00:00Z',
      'deleted': {
        'tasks': [101],
      },
    });

    final row =
        (await db.query('tasks', where: 'id = ?', whereArgs: [taskId])).single;
    expect(row['deleted_at'], isNotNull);
    expect(row['sync_status'], 'synced');

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(SyncIncrementalPull.cursorKey),
      '2026-08-21T00:00:00Z',
    );
  });

  test('不同 Cloud 账号使用独立 pull cursor', () async {
    final db = await LocalDb().database;

    await const SyncIncrementalPull(accountId: 7).applyChanges(db, {
      'server_time': '2026-08-21T00:10:00Z',
      'deleted': <String, dynamic>{},
    });
    await const SyncIncrementalPull(accountId: 8).applyChanges(db, {
      'server_time': '2026-08-21T00:20:00Z',
      'deleted': <String, dynamic>{},
    });

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('${SyncIncrementalPull.cursorKey}_user_7'),
      '2026-08-21T00:10:00Z',
    );
    expect(
      prefs.getString('${SyncIncrementalPull.cursorKey}_user_8'),
      '2026-08-21T00:20:00Z',
    );
  });

  test('pending 本地修改遇到远端删除会转 conflict 而不是被删除', () async {
    final db = await LocalDb().database;
    final listId = await insertList(db);
    final now = DateTime.now().toUtc().toIso8601String();
    final taskId = await db.insert('tasks', {
      'server_id': 102,
      'list_id': listId,
      'title': 'local pending',
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });

    await SyncIncrementalPull().applyChanges(db, {
      'server_time': '2026-08-21T00:01:00Z',
      'deleted': {
        'tasks': [102],
      },
    });

    final row =
        (await db.query('tasks', where: 'id = ?', whereArgs: [taskId])).single;
    expect(row['deleted_at'], isNull);
    expect(row['sync_status'], 'conflict');
  });

  test('pending ObservationTag 维度映射不会被远端增量静默覆盖', () async {
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final tagId = await db.insert('system_tags', {
      'server_id': 301,
      'name': '专注',
      'dimension_key': 'output',
      'icon': '🎯',
      'color': '#722ed1',
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });

    await const SyncIncrementalPull(accountId: 7).applyChanges(db, {
      'server_time': '2026-08-21T00:01:30Z',
      'system_tags': [
        {'id': 301, 'dimension_key': 'cognition'},
      ],
      'deleted': <String, dynamic>{},
    });

    final row = (await db.query(
      'system_tags',
      where: 'id = ?',
      whereArgs: [tagId],
    ))
        .single;
    expect(row['dimension_key'], 'output');
    expect(row['sync_status'], 'conflict');
  });

  test('tag tombstone 会删除 task_tags 关联后再删除本地 tag', () async {
    final db = await LocalDb().database;
    final listId = await insertList(db);
    final now = DateTime.now().toUtc().toIso8601String();
    final taskId = await db.insert('tasks', {
      'server_id': 103,
      'list_id': listId,
      'title': 'tag relation',
      'created_at': now,
      'updated_at': now,
      'sync_status': 'synced',
    });
    final tagId = await db.insert('tags', {
      'server_id': 201,
      'name': 'obsolete',
      'created_at': now,
      'updated_at': now,
      'sync_status': 'synced',
    });
    await db.insert('task_tags', {'task_id': taskId, 'tag_id': tagId});

    await SyncIncrementalPull().applyChanges(db, {
      'server_time': '2026-08-21T00:02:00Z',
      'deleted': {
        'tags': [201],
      },
    });

    expect(
      await db.query('task_tags', where: 'tag_id = ?', whereArgs: [tagId]),
      isEmpty,
    );
    expect(
      await db.query('tags', where: 'id = ?', whereArgs: [tagId]),
      isEmpty,
    );
  });
}
