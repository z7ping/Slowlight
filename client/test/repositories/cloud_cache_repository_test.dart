import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/cloud_cache_db.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/repositories/cloud_cache_repository.dart';
import 'package:slowlight/services/cloud_task_completion_cache.dart';
import 'package:slowlight/services/data_mode_manager.dart';
import 'package:slowlight/services/sync_service.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late String localDbPath;
  late String cloudDbPath;

  const userId = 42;
  final userJson = jsonEncode({
    'id': userId,
    'username': 'cloud_test',
    'email': 'cloud@example.com',
    'nickname': 'Cloud Test',
    'avatar': null,
    'created_at': '2026-08-21T00:00:00.000Z',
  });

  setUpAll(() async {
    final root = await useIsolatedTestDb('cloud_cache_repository');
    localDbPath = p.join(root, 'slowlight_offline.db');
    cloudDbPath = p.join(root, 'slowlight_cloud_cache_user_$userId.db');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'user_data': userJson});
    await CloudCacheDb().close();
    await LocalDb().close();
    await databaseFactory.deleteDatabase(localDbPath);
    await databaseFactory.deleteDatabase(cloudDbPath);
    await DataModeManager().setCloud();
  });

  tearDown(() async {
    SyncService().dispose2();
    await CloudCacheDb().close();
    await LocalDb().close();
    await databaseFactory.deleteDatabase(localDbPath);
    await databaseFactory.deleteDatabase(cloudDbPath);
  });

  test('已同步 Cloud row 对 UI 暴露 server id 而不是 cache local id', () async {
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listLocalId = await db.insert('lists', {
      'server_id': 501,
      'name': 'Remote List',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('tasks', {
      'server_id': 901,
      'list_id': listLocalId,
      'title': 'Remote Task',
      'created_at': now,
      'updated_at': now,
    });

    final task = (await CloudCacheRepository().getAllTasks()).single;
    expect(task.id, 901);
    expect(task.listId, 501);
    expect(task.list?.id, 501);
  });

  test('Cloud Today 包含今日、无日期、逾期未完成，并排除逾期已完成', () async {
    final db = await CloudCacheDb().database;
    final now = DateTime.now();
    final nowUtc = now.toUtc().toIso8601String();
    String dateKey(DateTime value) =>
        '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    final today = dateKey(now);
    final yesterday = dateKey(now.subtract(const Duration(days: 1)));
    final listLocalId = await db.insert('lists', {
      'server_id': 501,
      'name': 'Remote List',
      'created_at': nowUtc,
      'updated_at': nowUtc,
    });

    Future<void> insertTask({
      required int serverId,
      required String title,
      String? dueDate,
      bool completed = false,
    }) async {
      await db.insert('tasks', {
        'server_id': serverId,
        'list_id': listLocalId,
        'title': title,
        'due_date': dueDate,
        'is_completed': completed ? 1 : 0,
        'created_at': nowUtc,
        'updated_at': nowUtc,
      });
    }

    await insertTask(serverId: 901, title: 'Due today', dueDate: today);
    await insertTask(serverId: 902, title: 'No due date');
    await insertTask(serverId: 903, title: 'Overdue open', dueDate: yesterday);
    await insertTask(
      serverId: 904,
      title: 'Overdue completed',
      dueDate: yesterday,
      completed: true,
    );

    final titles =
        (await CloudCacheRepository().getTodayTasks()).map((task) => task.title).toSet();
    expect(titles, containsAll({'Due today', 'No due date', 'Overdue open'}));
    expect(titles, isNot(contains('Overdue completed')));
  });

  test('HabitLog 对外暴露 server id 及公开 Habit/Task 外键', () async {
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listLocalId = await db.insert('lists', {
      'server_id': 501,
      'name': 'Remote List',
      'created_at': now,
      'updated_at': now,
    });
    final taskLocalId = await db.insert('tasks', {
      'server_id': 901,
      'list_id': listLocalId,
      'title': 'Generated Task',
      'created_at': now,
      'updated_at': now,
    });
    final habitLocalId = await db.insert('habits', {
      'server_id': 701,
      'name': 'Remote Habit',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('habit_logs', {
      'server_id': 801,
      'habit_id': habitLocalId,
      'task_id': taskLocalId,
      'date': '2026-08-21',
      'created_at': now,
    });

    final logs = await CloudCacheRepository().getHabitLogs(701);
    final log = (logs['logs'] as List<dynamic>).single as Map<String, dynamic>;
    expect(log['id'], 801);
    expect(log['habit_id'], 701);
    expect(log['task_id'], 901);
  });

  test('离线新建 Task 使用负临时 id 并只进入 Cloud sync_queue', () async {
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('lists', {
      'server_id': 501,
      'name': 'Remote List',
      'created_at': now,
      'updated_at': now,
    });

    final task = await CloudCacheRepository().createTask(
      listId: 501,
      title: 'Offline Task',
    );

    expect(task.id, lessThan(0));
    expect(task.listId, 501);

    final queue = await db.query('sync_queue');
    expect(queue, hasLength(1));
    expect(queue.single['entity_type'], 'tasks');
    expect(queue.single['operation'], 'create');

    final localDb = await LocalDb().database;
    expect(await localDb.query('tasks'), isEmpty);
  });

  test('离线更新可使用负临时 id 定位同一 cache row', () async {
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('lists', {
      'server_id': 501,
      'name': 'Remote List',
      'created_at': now,
      'updated_at': now,
    });

    final repo = CloudCacheRepository();
    final created = await repo.createTask(listId: 501, title: 'Before');
    final updated = await repo.updateTask(
      taskId: created.id,
      listId: 501,
      title: 'After',
    );

    expect(updated.id, created.id);
    expect(updated.title, 'After');
    final queue = await db.query('sync_queue');
    expect(queue, hasLength(1));
    expect(queue.single['operation'], 'create');
  });

  test('server-backed Task 离线完成保存 completion intent 与 update 屏障', () async {
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final listLocalId = await db.insert('lists', {
      'server_id': 501,
      'name': 'Remote List',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('tasks', {
      'server_id': 901,
      'list_id': listLocalId,
      'title': 'Remote Task',
      'created_at': now,
      'updated_at': now,
    });

    final completion = CloudTaskCompletionCache();
    final completed = await completion.toggle(901);
    expect(completed.isCompleted, isTrue);

    final queue = await db.query('sync_queue');
    expect(queue, hasLength(1));
    expect(queue.single['operation'], 'update');

    var intents = await db.query('sync_intents');
    expect(intents, hasLength(1));
    expect(intents.single['intent'], 'completion');
    expect(intents.single['value'], '1');

    final reopened = await completion.toggle(901);
    expect(reopened.isCompleted, isFalse);
    intents = await db.query('sync_intents');
    expect(intents, hasLength(1));
    expect(intents.single['value'], '0');
    expect(await db.query('sync_queue'), hasLength(1));
  });

  test('离线新建 Task 再完成仍保留 create queue，并单独记录完成意图', () async {
    final db = await CloudCacheDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('lists', {
      'server_id': 501,
      'name': 'Remote List',
      'created_at': now,
      'updated_at': now,
    });

    final created = await CloudCacheRepository().createTask(
      listId: 501,
      title: 'Offline Task',
    );
    final completed = await CloudTaskCompletionCache().toggle(created.id);

    expect(completed.id, created.id);
    expect(completed.isCompleted, isTrue);
    final queue = await db.query('sync_queue');
    expect(queue, hasLength(1));
    expect(queue.single['operation'], 'create');
    final intents = await db.query('sync_intents');
    expect(intents, hasLength(1));
    expect(intents.single['value'], '1');
  });
}
