import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/services/local_today_review_service.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String dbPath;

  setUpAll(() async {
    dbPath = p.join(
      await useIsolatedTestDb('today_review'),
      'slowlight_offline.db',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);

    final db = await LocalDb().database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS work_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_type TEXT NOT NULL,
        task_id INTEGER,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        duration_sec INTEGER DEFAULT 0,
        device TEXT DEFAULT '',
        system_tag_id INTEGER,
        created_at TEXT NOT NULL
      )
    ''');
  });

  tearDown(() async {
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
  });

  test('Local Today Review 对齐 Habit Task Focus 与 SystemTag 事实/差值', () async {
    final db = await LocalDb().database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final listId = await db.insert('lists', {
      'name': '默认',
      'created_at': _localIso(today, 8),
      'updated_at': _localIso(today, 8),
    });
    final tagId = await db.insert('system_tags', {
      'name': '产出',
      'icon': '🛠️',
      'color': '#1890ff',
      'created_at': _localIso(today, 8),
      'updated_at': _localIso(today, 8),
    });
    final habitId = await db.insert('habits', {
      'name': '阅读',
      'created_at': _localIso(weekAgo, 8),
      'updated_at': _localIso(today, 8),
    });

    await db.insert('habit_logs', {
      'habit_id': habitId,
      'date': _date(today),
      'created_at': _localIso(today, 9),
    });
    await db.insert('habit_logs', {
      'habit_id': habitId,
      'date': _date(weekAgo),
      'created_at': _localIso(weekAgo, 9),
    });

    await _insertCompletedTask(
      db,
      listId: listId,
      title: '今天完成',
      createdAt: _localIso(today, 9),
      completedAt: _localIso(today, 10),
      outputLevel: 'A',
      isMilestone: true,
    );
    await _insertCompletedTask(
      db,
      listId: listId,
      title: '昨天完成',
      createdAt: _localIso(yesterday, 9),
      completedAt: _localIso(yesterday, 10),
    );
    await _insertCompletedTask(
      db,
      listId: listId,
      title: '上周完成',
      createdAt: _localIso(weekAgo, 9),
      completedAt: _localIso(weekAgo, 10),
    );

    await _insertWorkSession(
      db,
      day: today,
      durationSeconds: 600,
      systemTagId: tagId,
    );
    await _insertWorkSession(
      db,
      day: today,
      durationSeconds: 30,
      systemTagId: tagId,
      hour: 11,
    );
    await _insertWorkSession(
      db,
      day: yesterday,
      durationSeconds: 300,
      systemTagId: tagId,
    );
    await _insertWorkSession(
      db,
      day: weekAgo,
      durationSeconds: 60,
      systemTagId: tagId,
    );

    final review = await LocalTodayReviewService().computeTodayReview();
    final facts = review['facts'] as Map<String, dynamic>;
    final patterns = review['patterns'] as Map<String, dynamic>;

    expect(facts['habit_checked'], 1);
    expect(facts['habit_total'], 1);
    expect(facts['task_completed'], 1);
    expect(facts['task_created'], 1);
    expect(facts['focus_minutes'], 11);
    expect(facts['focus_count'], 2);

    final distribution = facts['tag_distribution'] as List<dynamic>;
    expect(distribution, hasLength(1));
    expect(distribution.first['tag_id'], tagId);
    expect(distribution.first['name'], '产出');
    expect(distribution.first['icon'], '🛠️');
    expect(distribution.first['minutes'], 11);

    final completedTasks = facts['today_completed_tasks'] as List<dynamic>;
    expect(completedTasks, hasLength(1));
    expect(completedTasks.first['title'], '今天完成');
    expect(completedTasks.first['output_level'], 'A');
    expect(completedTasks.first['is_milestone'], isTrue);

    expect(patterns['habit_delta'], 1);
    expect(patterns['habit_week_delta'], 0);
    expect(patterns['task_delta'], 0);
    expect(patterns['task_week_delta'], 0);
    expect(patterns['focus_delta'], 6);
    expect(patterns['focus_week_delta'], 10);
    expect(review['questions'], isEmpty);
  });

  test('没有 work_sessions 表时 Local Review 仍可用', () async {
    final db = await LocalDb().database;
    await db.execute('DROP TABLE work_sessions');

    final review = await LocalTodayReviewService().computeTodayReview();
    final facts = review['facts'] as Map<String, dynamic>;
    final patterns = review['patterns'] as Map<String, dynamic>;

    expect(facts['focus_minutes'], 0);
    expect(facts['focus_count'], 0);
    expect(facts['tag_distribution'], isEmpty);
    expect(patterns['focus_delta'], 0);
    expect(patterns['focus_week_delta'], 0);
  });
}

Future<void> _insertCompletedTask(
  Database db, {
  required int listId,
  required String title,
  required String createdAt,
  required String completedAt,
  String outputLevel = '',
  bool isMilestone = false,
}) async {
  await db.insert('tasks', {
    'list_id': listId,
    'title': title,
    'is_completed': 1,
    'completed_at': completedAt,
    'task_type': 'daily',
    'output_level': outputLevel,
    'is_milestone': isMilestone ? 1 : 0,
    'created_at': createdAt,
    'updated_at': completedAt,
  });
}

Future<void> _insertWorkSession(
  Database db, {
  required DateTime day,
  required int durationSeconds,
  required int systemTagId,
  int hour = 10,
}) async {
  final endedLocal = DateTime(day.year, day.month, day.day, hour);
  final startedLocal = endedLocal.subtract(Duration(seconds: durationSeconds));
  await db.insert('work_sessions', {
    'session_type': 'work',
    'started_at': startedLocal.toUtc().toIso8601String(),
    'ended_at': endedLocal.toUtc().toIso8601String(),
    'duration_sec': durationSeconds,
    'device': 'test',
    'system_tag_id': systemTagId,
    'created_at': startedLocal.toUtc().toIso8601String(),
  });
}

String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _localIso(DateTime day, int hour) =>
    DateTime(day.year, day.month, day.day, hour).toIso8601String();
