import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/services/sync_incremental_pull.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late String dbPath;

  // The server returns all six collections in every changes response.
  const completeCollections = <String, Object?>{
    'lists': <Object?>[],
    'tags': <Object?>[],
    'system_tags': <Object?>[],
    'habits': <Object?>[],
    'tasks': <Object?>[],
    'habit_logs': <Object?>[],
  };
  const emptyDeleted = <String, Object?>{
    'lists': <int>[],
    'tags': <int>[],
    'system_tags': <int>[],
    'habits': <int>[],
    'tasks': <int>[],
    'habit_logs': <int>[],
  };

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

  test('缺失完整删除清单或分类时不修改数据、不推进游标', () async {
    final db = await LocalDb().database;
    final listId = await insertList(db);
    final now = DateTime.now().toUtc().toIso8601String();
    final taskId = await db.insert('tasks', {
      'server_id': 501, 'list_id': listId, 'title': '保留',
      'created_at': now, 'updated_at': now,
      'sync_status': 'synced',
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SyncIncrementalPull.cursorKey, '2026-08-21T00:00:00Z');
    final complete = <String, dynamic>{
      ...completeCollections,
      'server_time': '2026-08-21T01:00:00Z',
      'deleted': {...emptyDeleted, 'tasks': [501]},
    };
    await expectLater(
      SyncIncrementalPull().applyChanges(db, {
        ...complete,
        'deleted': {'tasks': [501]},
      }),
      throwsFormatException,
    );
    await expectLater(
      SyncIncrementalPull().applyChanges(db, {
        ...complete,
        'system_tags': null,
      }),
      throwsFormatException,
    );
    await expectLater(
      SyncIncrementalPull().applyChanges(db, {
        ...complete,
        'deleted': {...emptyDeleted, 'tasks': ['not-an-id']},
      }),
      throwsFormatException,
    );
    await expectLater(
      SyncIncrementalPull().applyChanges(db, {
        ...complete,
        'server_time': 'unknown',
      }),
      throwsFormatException,
    );
    expect(
      (await db.query('tasks', where: 'id = ?', whereArgs: [taskId]))
          .single['deleted_at'],
      isNull,
    );
    expect(
      prefs.getString(SyncIncrementalPull.cursorKey),
      '2026-08-21T00:00:00Z',
    );
  });

  test('更新维度或删除中途 SQL 失败会回滚整批并保留原游标', () async {
    final db = await LocalDb().database;
    final listId = await insertList(db);
    final now = DateTime.now().toUtc().toIso8601String();
    final taskId = await db.insert('tasks', {
      'server_id': 601, 'list_id': listId, 'title': '保留在云端',
      'created_at': now, 'updated_at': now, 'sync_status': 'synced',
    });
    final tagId = await db.insert('tags', {
      'server_id': 602, 'name': '事务回滚标签', 'color': '#abcdef',
      'created_at': now, 'updated_at': now, 'sync_status': 'synced',
    });
    await db.execute('''
      CREATE TRIGGER abort_tag_delete BEFORE DELETE ON tags
      BEGIN SELECT RAISE(ABORT, 'rollback test'); END
    ''');
    final prefs = await SharedPreferences.getInstance();

    await expectLater(
      SyncIncrementalPull().applyChanges(db, {
        ...completeCollections,
        'server_time': '2026-08-21T02:00:00Z',
        'deleted': {
          ...emptyDeleted,
          'tasks': [601], 'tags': [602],
        },
      }),
      throwsA(isA<Exception>()),
    );
    expect(
      (await db.query('tasks', where: 'id = ?', whereArgs: [taskId]))
          .single['deleted_at'],
      isNull,
    );
    expect(await db.query('tags', where: 'id = ?', whereArgs: [tagId]),
        hasLength(1));
    expect(prefs.getString(SyncIncrementalPull.cursorKey), isNull);
  });

  test('旧服务端时间不能回退账户游标', () async {
    final db = await LocalDb().database;
    final pull = const SyncIncrementalPull(accountId: 12);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '${SyncIncrementalPull.cursorKey}_user_12',
      '2026-08-21T04:00:00Z',
    );
    await expectLater(
      pull.applyChanges(db, {
        ...completeCollections,
        'server_time': '2026-08-21T03:00:00Z',
        'deleted': {...emptyDeleted},
      }),
      throwsFormatException,
    );
    expect(
      prefs.getString('${SyncIncrementalPull.cursorKey}_user_12'),
      '2026-08-21T04:00:00Z',
    );
  });

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
      ...completeCollections,
      'server_time': '2026-08-21T00:00:00Z',
      'deleted': {
        ...emptyDeleted,
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
      ...completeCollections,
      'server_time': '2026-08-21T00:10:00Z',
      'deleted': {...emptyDeleted},
    });
    await const SyncIncrementalPull(accountId: 8).applyChanges(db, {
      ...completeCollections,
      'server_time': '2026-08-21T00:20:00Z',
      'deleted': {...emptyDeleted},
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
      ...completeCollections,
      'server_time': '2026-08-21T00:01:00Z',
      'deleted': {
        ...emptyDeleted,
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
      ...completeCollections,
      'server_time': '2026-08-21T00:01:30Z',
      'system_tags': [
        {'id': 301, 'dimension_key': 'cognition'},
      ],
      'deleted': {...emptyDeleted},
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
      ...completeCollections,
      'server_time': '2026-08-21T00:02:00Z',
      'deleted': {
        ...emptyDeleted,
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
