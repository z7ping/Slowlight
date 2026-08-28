import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_behavior_event_schema.dart';
import 'package:slowlight/db/local_db.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late String dbPath;

  setUpAll(() async {
    dbPath = p.join(
      await useIsolatedTestDb('behavior_event_schema'),
      'slowlight_offline.db',
    );
  });

  setUp(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
    LocalBehaviorEventSchema.resetForTest();
    await LocalBehaviorEventSchema.ensureReady();
  });

  tearDown(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
    LocalBehaviorEventSchema.resetForTest();
  });

  test('Task 完成生成事件，取消完成撤销事件', () async {
    final db = await LocalDb().database;
    final now = DateTime.now().toIso8601String();
    final listId = await db.insert('lists', {
      'name': '默认',
      'created_at': now,
      'updated_at': now,
    });
    final taskId = await db.insert('tasks', {
      'list_id': listId,
      'title': '完成测试',
      'created_at': now,
      'updated_at': now,
    });

    await db.update(
      'tasks',
      {'is_completed': 1, 'completed_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [taskId],
    );

    var events = await db.query(
      'behavior_events',
      where: "event_type = 'task_completed' AND entity_id = ?",
      whereArgs: [taskId],
    );
    expect(events, hasLength(1));
    expect(events.first['entity_type'], 'task');

    await db.update(
      'tasks',
      {'is_completed': 0, 'completed_at': null, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [taskId],
    );

    events = await db.query(
      'behavior_events',
      where: "event_type = 'task_completed' AND entity_id = ?",
      whereArgs: [taskId],
    );
    expect(events, isEmpty);
  });

  test('Habit 打卡生成事件，删除该日打卡只撤销该日事件', () async {
    final db = await LocalDb().database;
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final today = _date(now);
    final yesterday = _date(now.subtract(const Duration(days: 1)));
    final habitId = await db.insert('habits', {
      'name': '阅读',
      'duration_min': 20,
      'created_at': nowIso,
      'updated_at': nowIso,
    });

    await db.insert('habit_logs', {
      'habit_id': habitId,
      'date': yesterday,
      'duration_min': 10,
      'created_at': now.subtract(const Duration(days: 1)).toIso8601String(),
    });
    await db.insert('habit_logs', {
      'habit_id': habitId,
      'date': today,
      'duration_min': 20,
      'created_at': nowIso,
    });

    var events = await db.query(
      'behavior_events',
      where: "event_type = 'habit_checked' AND entity_id = ?",
      whereArgs: [habitId],
    );
    expect(events, hasLength(2));

    await db.delete(
      'habit_logs',
      where: 'habit_id = ? AND date = ?',
      whereArgs: [habitId, today],
    );

    events = await db.query(
      'behavior_events',
      where: "event_type = 'habit_checked' AND entity_id = ?",
      whereArgs: [habitId],
    );
    expect(events, hasLength(1));
    expect(events.first['metadata'], '{"date":"$yesterday"}');
  });

  test('WorkSession 结束生成 session_ended，最少记录 1 分钟', () async {
    final db = await LocalDb().database;
    final started = DateTime.now().subtract(const Duration(seconds: 20));
    final sessionId = await db.insert('work_sessions', {
      'session_type': 'work',
      'started_at': started.toUtc().toIso8601String(),
      'duration_sec': 0,
      'device': 'test',
      'created_at': started.toUtc().toIso8601String(),
    });
    final ended = DateTime.now().toUtc().toIso8601String();

    await db.update(
      'work_sessions',
      {
        'ended_at': ended,
        'duration_sec': 20,
        'system_tag_id': null,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );

    final events = await db.query(
      'behavior_events',
      where: "event_type = 'session_ended' AND entity_id = ?",
      whereArgs: [sessionId],
    );
    expect(events, hasLength(1));
    expect(events.first['entity_type'], 'session');
    expect(events.first['duration_min'], 1);
  });
}

String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
