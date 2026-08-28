import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/services/local_analytics_service.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late String dbPath;

  setUpAll(() async {
    dbPath = p.join(await useIsolatedTestDb('analytics'), 'slowlight_offline.db');
  });

  setUp(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });

  tearDown(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });

  Future<int> createList(Database db) async {
    final now = DateTime.now().toIso8601String();
    return db.insert('lists', {
      'name': 'Inbox',
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<int> createTask(
    Database db, {
    required int listId,
    required String title,
    required DateTime createdAt,
    DateTime? completedAt,
    String outputLevel = '',
    String taskType = 'daily',
  }) {
    return db.insert('tasks', {
      'list_id': listId,
      'title': title,
      'is_completed': completedAt == null ? 0 : 1,
      'completed_at': completedAt?.toIso8601String(),
      'output_level': outputLevel,
      'task_type': taskType,
      'created_at': createdAt.toIso8601String(),
      'updated_at': (completedAt ?? createdAt).toIso8601String(),
    });
  }

  test('OutputStats 只统计有 output_level 的完成任务', () async {
    final db = await LocalDb().database;
    final listId = await createList(db);
    final now = DateTime.now();
    await createTask(
      db,
      listId: listId,
      title: 'output',
      createdAt: now,
      completedAt: now,
      outputLevel: 'A',
      taskType: 'main',
    );
    await createTask(
      db,
      listId: listId,
      title: 'ordinary',
      createdAt: now,
      completedAt: now,
    );

    final stats = await LocalAnalyticsService().getOutputStats();
    expect(stats['total_count'], 1);
    expect((stats['by_level'] as Map)['A'], 1);
    expect((stats['by_task_type'] as Map)['main'], 1);
    expect((stats['by_task_type'] as Map).containsKey('daily'), isFalse);
  });

  test('DailyTrend 完成率使用同一创建 cohort 且不会超过 100', () async {
    final db = await LocalDb().database;
    final listId = await createList(db);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = today.subtract(const Duration(days: 1));

    await createTask(
      db,
      listId: listId,
      title: 'today completed',
      createdAt: today,
      completedAt: today.add(const Duration(hours: 1)),
    );
    await createTask(
      db,
      listId: listId,
      title: 'today pending',
      createdAt: today.add(const Duration(minutes: 1)),
    );
    await createTask(
      db,
      listId: listId,
      title: 'old task completed today',
      createdAt: yesterday,
      completedAt: today.add(const Duration(hours: 2)),
    );

    final trend = await LocalAnalyticsService().getDailyTrend(days: 1);
    final point = trend.single;
    expect(point['task_completed'], 2);
    expect(point['task_total'], 2);
    expect(point['completion_rate'], 50);
    expect((point['completion_rate'] as int) <= 100, isTrue);
  });

  test('DimensionSummary 把 session_ended 纳入维度活动', () async {
    final db = await LocalDb().database;
    final now = DateTime.now();
    final timestamp = now.toIso8601String();
    final tagId = await db.insert('system_tags', {
      'name': '认知',
      'icon': '🧠',
      'color': '#1890ff',
      'created_at': timestamp,
      'updated_at': timestamp,
    });

    await db.execute('''
      CREATE TABLE behavior_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_type TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        system_tag_id INTEGER,
        duration_min INTEGER DEFAULT 0,
        occurred_at TEXT NOT NULL,
        metadata TEXT DEFAULT '{}',
        is_deleted INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    for (final type in ['task_completed', 'habit_checked', 'session_ended']) {
      await db.insert('behavior_events', {
        'event_type': type,
        'entity_type': type == 'task_completed'
            ? 'task'
            : type == 'habit_checked'
                ? 'habit'
                : 'session',
        'entity_id': 1,
        'system_tag_id': tagId,
        'duration_min': type == 'session_ended' ? 25 : 0,
        'occurred_at': timestamp,
        'created_at': timestamp,
      });
    }

    final summary = await LocalAnalyticsService().getDimensionSummary();
    final dimensions = summary['dimensions'] as List;
    final cognition = dimensions.firstWhere((d) => d['key'] == 'cognition');
    expect(cognition['value'], 3);

    final time = await LocalAnalyticsService().getTimeDistribution();
    expect(time['total_min'], 25);
    expect((time['tags'] as List).single['session_count'], 1);
  });
}
