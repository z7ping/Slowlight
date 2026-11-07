import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/db/local_behavior_event_schema.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/db/local_product_core_schema.dart';
import 'package:slowlight/services/local_today_timeline_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String dbPath;

  setUpAll(() async {
    dbPath = p.join(
      await useIsolatedTestDb('today_timeline'),
      'slowlight_offline.db',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalBehaviorEventSchema.resetForTest();
    await LocalDb().close();
    await databaseFactory.deleteDatabase(dbPath);
    await LocalProductCoreSchema.ensureReady();
    await LocalBehaviorEventSchema.ensureReady();
  });

  tearDown(() async {
    await LocalDb().close();
    LocalBehaviorEventSchema.resetForTest();
    await databaseFactory.deleteDatabase(dbPath);
  });

  test('真实时间点混排任务、习惯、专注、观察；撤销后事实立即消失', () async {
    final db = await LocalDb().database;
    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final iso = now.toUtc().toIso8601String();

    final listId = await db.insert('lists', {
      'name': '今日', 'created_at': iso, 'updated_at': iso,
    });
    final taskId = await db.insert('tasks', {
      'list_id': listId, 'title': '整理笔记',
      'is_completed': 0, 'created_at': iso, 'updated_at': iso,
    });
    await db.update('tasks',
      {'is_completed': 1, 'completed_at': iso},
      where: 'id = ?', whereArgs: [taskId]);

    final habitId = await db.insert('habits', {
      'name': '阅读', 'created_at': iso, 'updated_at': iso,
    });
    await db.insert('habit_logs', {
      'habit_id': habitId, 'date': date, 'created_at': iso,
    });
    // 补记昨天的习惯，实际归属昨天，不能算成今天的行为。
    final previous = now.subtract(const Duration(days: 1));
    final previousDate =
        '${previous.year.toString().padLeft(4, '0')}-'
        '${previous.month.toString().padLeft(2, '0')}-'
        '${previous.day.toString().padLeft(2, '0')}';
    await db.insert('habit_logs', {
      'habit_id': habitId, 'date': previousDate, 'created_at': iso,
    });
    final sessionId = await db.insert('work_sessions', {
      'session_type': 'work',
      'started_at': now.subtract(const Duration(minutes: 25)).toUtc().toIso8601String(),
      'ended_at': null, 'duration_sec': 1500,
      'created_at': iso,
    });
    await db.update('work_sessions', {'ended_at': iso},
      where: 'id = ?', whereArgs: [sessionId]);
    await db.insert('reflections', {
      'entry_type': 'observation',
      'content': '今天想记录一点变化',
      'created_at': iso, 'updated_at': iso,
    });

    final service = LocalTodayTimelineService();
    final rows = await service.getTodayTimeline();
    expect(rows.map((e) => e.kind).toSet(), {
      'task_completed', 'habit_checked', 'session_ended', 'observation',
    });
    expect(rows.length, 4);

    await db.update('tasks',
      {'is_completed': 0, 'completed_at': null},
      where: 'id = ?', whereArgs: [taskId]);
    await db.delete('habit_logs',
      where: 'habit_id = ?', whereArgs: [habitId]);
    final corrected = await service.getTodayTimeline();
    expect(corrected.map((e) => e.kind).toSet(), {
      'session_ended', 'observation',
    });
  });
  test('周期观察总量不受40条可见事件截断，按本地日历跨期统计', () async {
    final db = await LocalDb().database;
    final now = DateTime.now();
    final today = now.toUtc().toIso8601String();
    for (var i = 0; i < 45; i++) {
      await db.insert('reflections', {
        'entry_type': 'observation',
        'content': '今日观察$i',
        'created_at': today,
        'updated_at': today,
      });
    }
    final older = DateTime(now.year, now.month, now.day - 10, 12)
        .toUtc().toIso8601String();
    await db.insert('reflections', {
      'entry_type': 'observation',
      'content': '十天前的观察',
      'created_at': older,
      'updated_at': older,
    });
    await db.insert('reflections', {
      'entry_type': 'observation',
      'content': '已删除',
      'created_at': today,
      'updated_at': today,
      'deleted_at': today,
    });
    await db.insert('reflections', {
      'entry_type': 'reflection',
      'content': '反思不是观察',
      'created_at': today,
      'updated_at': today,
    });

    final service = LocalTodayTimelineService();
    final daily = await service.getPeriodTimeline();
    final rolling = await service.getPeriodTimeline(period: 'month');
    expect(daily.observationCount, 45);
    expect(rolling.observationCount, 46);
    expect(daily.items.length, 40);
    expect(rolling.items.length, 40);
    expect(rolling.items.first.kind, 'observation');
    await expectLater(
      service.getPeriodTimeline(period: 'year'), throwsArgumentError,
    );
  });

}
