import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:slowlight/db/local_db.dart';
import 'package:slowlight/services/reminder_local.dart';

import '../helpers/isolated_test_db.dart';

void main() {
  late ReminderLocal reminderLocal;
  late String dbPath;

  setUpAll(() async {
    dbPath = p.join(
      await useIsolatedTestDb('reminder_local_stats'),
      'slowlight_offline.db',
    );
  });

  setUp(() async {
    await LocalDb().close();
    await deleteDatabase(dbPath);
    reminderLocal = ReminderLocal();
  });

  tearDown(() async {
    await LocalDb().close();
  });

  Future<void> insertReminderSession({
    required String type,
    required int durationSeconds,
    bool skipped = false,
  }) async {
    final db = await LocalDb().database;
    final now = DateTime.now();
    // 测试统计按 started_at 的本地日历日期归属。固定在当天中午附近，
    // 避免 CI 恰好在午夜后运行时，“向前减 30 分钟”跨到前一天。
    final startedAt = DateTime(now.year, now.month, now.day, 12);
    final endedAt = startedAt.add(Duration(seconds: durationSeconds));
    await db.insert('reminder_sessions', {
      'type': type,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt.toIso8601String(),
      'duration_seconds': durationSeconds,
      'skipped': skipped ? 1 : 0,
      'synced': 0,
      'created_at': startedAt.toIso8601String(),
    });
  }

  test('新安装的提醒模式默认全屏，已有窗口偏好仍可保留', () async {
    final db = await LocalDb().database;
    final columns = await db.rawQuery('PRAGMA table_info(reminder_config)');
    final modeColumn = columns.firstWhere((row) => row['name'] == 'lock_screen_mode');
    expect(modeColumn['dflt_value'], "'fullscreen'");

    await reminderLocal.saveConfig(
      workMinutes: 25,
      microRestSeconds: 20,
      longRestMinutes: 5,
      microRestsBeforeLong: 2,
      lockScreenMode: 'window',
    );
    final saved = await reminderLocal.getConfig();
    expect(saved?['lock_screen_mode'], 'window');
  });

  test('今日统计只把实际完成的休息计入休息时长和完成轮次', () async {
    await insertReminderSession(type: 'work', durationSeconds: 1800);
    await insertReminderSession(type: 'rest', durationSeconds: 60);
    await insertReminderSession(type: 'rest', durationSeconds: 20, skipped: true);

    final stats = await reminderLocal.getTodayStats();

    expect(stats['total_work_seconds'], 1800);
    expect(stats['total_break_seconds'], 60);
    expect(stats['work_count'], 1);
    expect(stats['skip_count'], 1);
  });

  test('取消当前休息不会留下会被今日统计计算的休息记录', () async {
    await reminderLocal.startRest();

    await reminderLocal.cancelActiveRest();

    final stats = await reminderLocal.getTodayStats();
    expect(stats['total_break_seconds'], 0);
    expect(stats['work_count'], 0);
    expect(stats['skip_count'], 0);
  });
}
