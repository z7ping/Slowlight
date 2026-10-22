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
}
