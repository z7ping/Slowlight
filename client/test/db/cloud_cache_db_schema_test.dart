import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:slowlight/db/cloud_cache_db.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/services/data_mode_manager.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  const userId = 42;
  late String databasePath;

  setUpAll(() async {
    final root = await useIsolatedTestDb('cloud_cache_db_schema');
    databasePath = p.join(root, 'slowlight_cloud_cache_user_$userId.db');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'user_data': jsonEncode({
        'id': userId,
        'username': 'cloud_schema_test',
        'email': 'cloud@example.com',
        'created_at': '2026-08-21T00:00:00.000Z',
      }),
    });
    await CloudCacheDb().close();
    await LocalDb().close();
    await databaseFactory.deleteDatabase(databasePath);
    await databaseFactory.deleteDatabase(LocalDb.debugDatabasePathOverride!);
    await DataModeManager().setCloud();
  });

  tearDown(() async {
    await CloudCacheDb().close();
    await LocalDb().close();
    await databaseFactory.deleteDatabase(databasePath);
    await databaseFactory.deleteDatabase(LocalDb.debugDatabasePathOverride!);
    await DataModeManager().setLocal();
  });

  Future<Set<String>> columns(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'].toString()).toSet();
  }

  Future<void> expectRecordColumns(Database db) async {
    expect(await columns(db, 'habits'), containsAll([
      'record_type',
      'record_unit',
      'record_time_label',
      'allow_multiple_per_day', 'goal_period', 'goal_metric', 'goal_value',
    ]));
    expect(await columns(db, 'habit_logs'), containsAll([
      'count_value',
      'occurred_at', 'client_key',
    ]));
  }

  test('Cloud Cache 习惯与打卡字段覆盖 LocalDb 同名字段，防止再次漂移', () async {
    final cloudDb = await CloudCacheDb().database;
    final localDb = await LocalDb().database;
    for (final table in ['habits', 'habit_logs']) {
      final localColumns = await columns(localDb, table);
      final cloudColumns = await columns(cloudDb, table);
      expect(
        cloudColumns.containsAll(localColumns),
        isTrue,
        reason: table + ' 的 Cloud Cache 缺少本地记录字段：' +
            localColumns.difference(cloudColumns).toString(),
      );
    }
  });

  test('新 Cloud Cache 具备习惯记录类型及打卡计数/发生时间列', () async {
    final db = await CloudCacheDb().database;
    await expectRecordColumns(db);

    const now = '2026-10-23T02:43:18.835056Z';
    final habitId = await db.insert('habits', {
      'name': '喝水',
      'frequency': 'daily',
      'record_type': 'count',
      'record_unit': '杯',
      'record_time_label': '喝水时间',
      'created_at': now,
      'updated_at': now,
      'sync_status': 'synced',
    });
    await db.insert('habit_logs', {
      'habit_id': habitId,
      'date': '2026-10-23',
      'count_value': 2,
      'occurred_at': now,
      'created_at': now,
    });

    expect((await db.query('habits', where: 'id = ?', whereArgs: [habitId]))
        .single['record_type'], 'count');
    expect((await db.query('habit_logs')).single['count_value'], 2);
  });

  test('v4 Cloud Cache 原地升级 v6，保留旧习惯、打卡与待同步队列', () async {
    const now = '2026-10-23T02:43:18.835056Z';
    final oldDb = await openDatabase(
      databasePath,
      version: 4,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE habits (
            id INTEGER PRIMARY KEY,
            server_id INTEGER,
            name TEXT NOT NULL,
            frequency TEXT DEFAULT 'daily',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            sync_status TEXT DEFAULT 'synced'
          )
        ''');
        await db.execute('''
          CREATE TABLE habit_logs (
            id INTEGER PRIMARY KEY,
            habit_id INTEGER NOT NULL,
            date TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_queue (
            id INTEGER PRIMARY KEY,
            entity_type TEXT NOT NULL,
            entity_local_id INTEGER NOT NULL,
            operation TEXT NOT NULL
          )
        ''');
        await db.insert('habits', {
          'id': 7, 'server_id': 27,
          'name': '喝水', 'created_at': now, 'updated_at': now,
        });
        await db.insert('habit_logs', {
          'id': 8, 'habit_id': 7, 'date': '2026-10-23',
          'created_at': now,
        });
        await db.insert('sync_queue', {
          'id': 9, 'entity_type': 'habits',
          'entity_local_id': 7, 'operation': 'update',
        });
      },
    );
    await oldDb.close();

    final upgraded = await CloudCacheDb().database;
    await expectRecordColumns(upgraded);
    expect((await upgraded.rawQuery('PRAGMA user_version')).single.values.single, 7);
    final oldHabit = (await upgraded.query('habits', where: 'id = 7')).single;
    expect(oldHabit['server_id'], 27);
    expect(oldHabit['name'], '喝水');
    expect(oldHabit['record_type'], 'legacy');
    expect(oldHabit['record_unit'], '次');
    expect(oldHabit['record_time_label'], '');
    expect((await upgraded.query('habit_logs')).single['habit_id'], 7);
    expect((await upgraded.query('sync_queue')).single['entity_local_id'], 7);

    // 重现用户提供的 SQL 写入字段组合，原地升级后不再报缺失列。
    await upgraded.insert('habits', {
      'name': '散步', 'frequency': 'daily',
      'record_type': 'legacy', 'record_unit': '次',
      'record_time_label': '',
      'created_at': now, 'updated_at': now,
    });
    await upgraded.insert('habit_logs', {
      'habit_id': 7, 'date': '2026-10-23',
      'count_value': 1, 'occurred_at': now,
      'created_at': now,
    });

    await CloudCacheDb().close();
    final reopened = await CloudCacheDb().database;
    await expectRecordColumns(reopened);
    expect(await reopened.query('sync_queue'), hasLength(1));
  });

  test('v4 部分已存在记录字段时仅补缺列，不重复添加', () async {
    final oldDb = await openDatabase(
      databasePath,
      version: 4,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE habits (
            id INTEGER PRIMARY KEY,
            record_type TEXT NOT NULL DEFAULT 'legacy'
          )
        ''');
        await db.execute('''
          CREATE TABLE habit_logs (
            id INTEGER PRIMARY KEY,
            count_value INTEGER
          )
        ''');
      },
    );
    await oldDb.close();
    final upgraded = await CloudCacheDb().database;
    await expectRecordColumns(upgraded);
    expect((await upgraded.rawQuery('PRAGMA user_version')).single.values.single, 7);
  });
}
