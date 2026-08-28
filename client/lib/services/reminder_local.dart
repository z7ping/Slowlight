import 'package:sqflite/sqflite.dart';
import '../db/local_db.dart';

/// 休息提醒本地数据访问 — 先写本地，再异步同步服务端
class ReminderLocal {
  static final ReminderLocal _instance = ReminderLocal._();
  factory ReminderLocal() => _instance;
  ReminderLocal._();

  // ── 配置 ──

  Future<Map<String, dynamic>?> getConfig() async {
    final db = await LocalDb().database;
    final rows = await db.query('reminder_config', where: 'id = 1');
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> saveConfig({
    required int workMinutes,
    required int microRestSeconds,
    required int longRestMinutes,
    required int microRestsBeforeLong,
    required String lockScreenMode,
    int notifyBeforeSeconds = 30,
    bool autoLoop = true,
    bool autoStartOnLaunch = true,
    bool microRestStrict = false,
    bool longRestStrict = false,
    bool allowPostponeMicro = true,
    bool allowPostponeLong = true,
  }) async {
    final db = await LocalDb().database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
        'reminder_config',
        {
          'id': 1,
          'work_minutes': workMinutes,
          'micro_rest_seconds': microRestSeconds,
          'long_rest_minutes': longRestMinutes,
          'micro_rests_before_long': microRestsBeforeLong,
          'lock_screen_mode': lockScreenMode,
          'notify_before_seconds': notifyBeforeSeconds,
          'auto_loop': autoLoop ? 1 : 0,
          'auto_start_on_launch': autoStartOnLaunch ? 1 : 0,
          'micro_rest_strict': microRestStrict ? 1 : 0,
          'long_rest_strict': longRestStrict ? 1 : 0,
          'allow_postpone_micro': allowPostponeMicro ? 1 : 0,
          'allow_postpone_long': allowPostponeLong ? 1 : 0,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── 会话记录 ──

  /// 记录开始休息
  Future<int> startRest() async {
    try {
      final db = await LocalDb().database;
      final now = DateTime.now().toIso8601String();
      return await db.insert('reminder_sessions', {
        'type': 'rest',
        'started_at': now,
        'synced': 0,
        'created_at': now,
      });
    } catch (e) {
      return -1;
    }
  }

  /// 记录开始工作
  Future<int> startWork() async {
    try {
      final db = await LocalDb().database;
      final now = DateTime.now().toIso8601String();
      return await db.insert('reminder_sessions', {
        'type': 'work',
        'started_at': now,
        'synced': 0,
        'created_at': now,
      });
    } catch (e) {
      return -1;
    }
  }

  /// 结束休息
  Future<void> endRest({bool skipped = false}) async {
    try {
      final db = await LocalDb().database;
      final now = DateTime.now();
      // 找到最近一条未结束的 rest 记录
      final rows = await db.query(
        'reminder_sessions',
        where: 'type = ? AND ended_at IS NULL',
        whereArgs: ['rest'],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (rows.isEmpty) return;

      final row = rows.first;
      final startedAt = DateTime.parse(row['started_at'] as String);
      final duration = skipped ? 0 : now.difference(startedAt).inSeconds;

      await db.update(
        'reminder_sessions',
        {
          'ended_at': now.toIso8601String(),
          'duration_seconds': duration,
          'skipped': skipped ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    } catch (e) {
      // 表不存在时忽略
    }
  }

  /// 取消当前休息，不计入休息时长、完成轮次或跳过次数。
  Future<void> cancelActiveRest() async {
    try {
      final db = await LocalDb().database;
      await db.delete(
        'reminder_sessions',
        where: 'type = ? AND ended_at IS NULL',
        whereArgs: ['rest'],
      );
    } catch (e) {
      // 表不存在时忽略
    }
  }

  /// 结束工作
  Future<void> endWork() async {
    try {
      final db = await LocalDb().database;
      final now = DateTime.now();
      final rows = await db.query(
        'reminder_sessions',
        where: 'type = ? AND ended_at IS NULL',
        whereArgs: ['work'],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (rows.isEmpty) return;

      final row = rows.first;
      final startedAt = DateTime.parse(row['started_at'] as String);
      final duration = now.difference(startedAt).inSeconds;

      await db.update(
        'reminder_sessions',
        {
          'ended_at': now.toIso8601String(),
          'duration_seconds': duration,
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    } catch (e) {
      // 表不存在时忽略
    }
  }

  /// 跳过休息
  Future<void> skipRest() async {
    await endRest(skipped: true);
  }

  // ── 统计 ──


  /// 获取今日增强统计（包含所有维度）
  Future<Map<String, dynamic>> getTodayStats() async {
    try {
      final db = await LocalDb().database;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final todayPattern = '$today%';

      // 工作统计
      final workRows = await db.rawQuery('''
        SELECT
          COALESCE(SUM(duration_seconds), 0) as total_seconds,
          COUNT(*) as count,
          COALESCE(AVG(duration_seconds), 0) as avg_seconds,
          COALESCE(MAX(duration_seconds), 0) as max_seconds,
          COALESCE(MIN(duration_seconds), 0) as min_seconds
        FROM reminder_sessions
        WHERE type = 'work' AND ended_at IS NOT NULL
        AND started_at LIKE ?
      ''', [todayPattern]);

      // 休息统计（有效）
      final restRows = await db.rawQuery('''
        SELECT
          COALESCE(SUM(CASE WHEN skipped = 0 THEN duration_seconds ELSE 0 END), 0) as total_seconds,
          COALESCE(SUM(CASE WHEN skipped = 0 THEN 1 ELSE 0 END), 0) as count,
          COALESCE(AVG(CASE WHEN skipped = 0 THEN duration_seconds ELSE NULL END), 0) as avg_seconds,
          COALESCE(MAX(CASE WHEN skipped = 0 THEN duration_seconds ELSE NULL END), 0) as max_seconds,
          COALESCE(SUM(CASE WHEN skipped != 0 THEN 1 ELSE 0 END), 0) as skips
        FROM reminder_sessions
        WHERE type = 'rest' AND ended_at IS NOT NULL
        AND started_at LIKE ?
      ''', [todayPattern]);

      // 今日时间区间
      final rangeRows = await db.rawQuery('''
        SELECT
          MIN(started_at) as day_start,
          MAX(ended_at) as day_end,
          MAX(CASE WHEN ended_at IS NULL THEN started_at ELSE NULL END) as active_start
        FROM reminder_sessions
        WHERE started_at LIKE ?
      ''', [todayPattern]);

      // 最长连续不跳过
      final streakResult = await _calcLongestNoSkipStreak(db, todayPattern);

      final workTotal = (workRows.first['total_seconds'] as int?) ?? 0;
      final workCount = (workRows.first['count'] as int?) ?? 0;
      final workAvg = ((workRows.first['avg_seconds'] as num?) ?? 0).round();
      final workMax = (workRows.first['max_seconds'] as int?) ?? 0;
      final workMin = (workRows.first['min_seconds'] as int?) ?? 0;
      final restTotal = (restRows.first['total_seconds'] as int?) ?? 0;
      final restCount = (restRows.first['count'] as int?) ?? 0;
      final restAvg = ((restRows.first['avg_seconds'] as num?) ?? 0).round();
      final restMax = (restRows.first['max_seconds'] as int?) ?? 0;
      final skipCount = (restRows.first['skips'] as int?) ?? 0;
      final dayStart = rangeRows.first['day_start'] as String?;
      final dayEnd = rangeRows.first['day_end'] as String?;
      final activeStart = rangeRows.first['active_start'] as String?;

      final totalReminders = restCount + skipCount;
      final skipRate = totalReminders > 0 ? skipCount / totalReminders : 0.0;
      final workRestRatio = restTotal > 0 ? workTotal / restTotal : 0.0;

      return {
        'work_count': workCount,
        'total_work_seconds': workTotal,
        'work_avg_seconds': workAvg,
        'work_max_seconds': workMax,
        'work_min_seconds': workMin,
        'rest_count': restCount,
        'total_break_seconds': restTotal,
        'rest_avg_seconds': restAvg,
        'rest_max_seconds': restMax,
        'skip_count': skipCount,
        'skip_rate': skipRate,
        'work_rest_ratio': workRestRatio,
        'longest_no_skip_streak': streakResult,
        'day_start': dayStart ?? '',
        'day_end': dayEnd ?? '',
        'is_active': activeStart != null,
      };
    } catch (e) {
      return _emptyTodayStats();
    }
  }
  Map<String, dynamic> _emptyTodayStats() {
    return {
      'work_count': 0, 'total_work_seconds': 0, 'work_avg_seconds': 0,
      'work_max_seconds': 0, 'work_min_seconds': 0,
      'rest_count': 0, 'total_break_seconds': 0, 'rest_avg_seconds': 0,
      'rest_max_seconds': 0, 'skip_count': 0, 'skip_rate': 0.0,
      'work_rest_ratio': 0.0, 'longest_no_skip_streak': 0,
      'day_start': '', 'day_end': '', 'is_active': false,
    };
  }

  /// 计算最长连续不跳过
  Future<int> _calcLongestNoSkipStreak(Database db, String datePattern) async {
    try {
      final rows = await db.rawQuery('''
        SELECT skipped FROM reminder_sessions
        WHERE type = 'rest' AND ended_at IS NOT NULL
        AND started_at LIKE ?
        ORDER BY started_at ASC
      ''', [datePattern]);
      int maxStreak = 0;
      int current = 0;
      for (final row in rows) {
        if ((row['skipped'] as int?) == 0) {
          current++;
          if (current > maxStreak) maxStreak = current;
        } else {
          current = 0;
        }
      }
      return maxStreak;
    } catch (e) {
      return 0;
    }
  }

  // ── 回顾：详细日志 ──

  /// 获取指定日期的所有会话记录（用于日志时间线）
  Future<List<Map<String, dynamic>>> getDateSessions(String date) async {
    try {
      final db = await LocalDb().database;
      final pattern = '$date%';
      return await db.rawQuery('''
        SELECT id, type, started_at, ended_at, duration_seconds, skipped
        FROM reminder_sessions
        WHERE started_at LIKE ?
        ORDER BY started_at DESC
      ''', [pattern]);
    } catch (e) {
      return [];
    }
  }

  // ── 回顾：多日聚合 ──

  /// 获取最近 N 天的每日聚合统计
  Future<List<Map<String, dynamic>>> getDailyAggregatedStats({required int days}) async {
    try {
      final db = await LocalDb().database;
      final since = DateTime.now().subtract(Duration(days: days - 1));
      final sinceStr = since.toIso8601String().substring(0, 10);

      return await db.rawQuery('''
        SELECT
          substr(started_at, 1, 10) as date,
          SUM(CASE WHEN type = 'work' AND ended_at IS NOT NULL THEN duration_seconds ELSE 0 END) as work_seconds,
          COUNT(CASE WHEN type = 'work' AND ended_at IS NOT NULL THEN 1 END) as work_count,
          SUM(CASE WHEN type = 'rest' AND skipped = 0 AND ended_at IS NOT NULL THEN duration_seconds ELSE 0 END) as rest_seconds,
          COUNT(CASE WHEN type = 'rest' AND skipped = 0 AND ended_at IS NOT NULL THEN 1 END) as rest_count,
          SUM(CASE WHEN type = 'rest' AND skipped != 0 AND ended_at IS NOT NULL THEN 1 ELSE 0 END) as skip_count,
          MIN(started_at) as day_start,
          MAX(ended_at) as day_end
        FROM reminder_sessions
        WHERE started_at >= ?
        GROUP BY substr(started_at, 1, 10)
        ORDER BY date ASC
      ''', [sinceStr]);
    } catch (e) {
      return [];
    }
  }
  // ── 回顾：时段热力图 ──

  /// 获取最近 N 天的按小时工作分布（0-23）
  Future<Map<int, int>> getHourlyWorkDistribution({required int days}) async {
    try {
      final db = await LocalDb().database;
      final since = DateTime.now().subtract(Duration(days: days - 1));
      final sinceStr = since.toIso8601String().substring(0, 10);

      final rows = await db.rawQuery('''
        SELECT
          CAST(substr(started_at, 12, 2) AS INTEGER) as hour,
          SUM(CASE WHEN type = 'work' AND ended_at IS NOT NULL THEN duration_seconds ELSE 0 END) as total
        FROM reminder_sessions
        WHERE started_at >= ? AND type = 'work' AND ended_at IS NOT NULL
        GROUP BY hour
        ORDER BY hour
      ''', [sinceStr]);

      final result = <int, int>{};
      for (final row in rows) {
        result[row['hour'] as int] = (row['total'] as int?) ?? 0;
      }
      return result;
    } catch (e) {
      return {};
    }
  }

  // ── 回顾：工作日 vs 周末 ──

  /// 获取工作日和周末的日均对比
  Future<Map<String, dynamic>> getWeekdayWeekendComparison({required int days}) async {
    try {
      final db = await LocalDb().database;
      final since = DateTime.now().subtract(Duration(days: days - 1));
      final sinceStr = since.toIso8601String().substring(0, 10);

      final rows = await db.rawQuery('''
        SELECT
          substr(started_at, 1, 10) as date,
          SUM(CASE WHEN type = 'work' AND ended_at IS NOT NULL THEN duration_seconds ELSE 0 END) as work_seconds,
          COUNT(CASE WHEN type = 'rest' AND skipped = 0 AND ended_at IS NOT NULL THEN 1 END) as rest_count,
          SUM(CASE WHEN type = 'rest' AND skipped != 0 AND ended_at IS NOT NULL THEN 1 ELSE 0 END) as skip_count
        FROM reminder_sessions
        WHERE started_at >= ?
        GROUP BY substr(started_at, 1, 10)
      ''', [sinceStr]);

      int weekdayWorkTotal = 0, weekdayRestTotal = 0, weekdaySkipTotal = 0;
      int weekdayDays = 0;
      int weekendWorkTotal = 0, weekendRestTotal = 0, weekendSkipTotal = 0;
      int weekendDays = 0;

      for (final row in rows) {
        final date = DateTime.parse(row['date'] as String);
        final work = (row['work_seconds'] as int?) ?? 0;
        final rest = (row['rest_count'] as int?) ?? 0;
        final skips = (row['skip_count'] as int?) ?? 0;

        if (date.weekday <= 5) {
          weekdayWorkTotal += work;
          weekdayRestTotal += rest;
          weekdaySkipTotal += skips;
          weekdayDays++;
        } else {
          weekendWorkTotal += work;
          weekendRestTotal += rest;
          weekendSkipTotal += skips;
          weekendDays++;
        }
      }

      return {
        'weekday_avg_work_seconds': weekdayDays > 0 ? (weekdayWorkTotal ~/ weekdayDays) : 0,
        'weekday_avg_rest_count': weekdayDays > 0 ? (weekdayRestTotal / weekdayDays).toStringAsFixed(1) : '0',
        'weekday_avg_skip_count': weekdayDays > 0 ? (weekdaySkipTotal / weekdayDays).toStringAsFixed(1) : '0',
        'weekend_avg_work_seconds': weekendDays > 0 ? (weekendWorkTotal ~/ weekendDays) : 0,
        'weekend_avg_rest_count': weekendDays > 0 ? (weekendRestTotal / weekendDays).toStringAsFixed(1) : '0',
        'weekend_avg_skip_count': weekendDays > 0 ? (weekendSkipTotal / weekendDays).toStringAsFixed(1) : '0',
        'weekday_days': weekdayDays,
        'weekend_days': weekendDays,
      };
    } catch (e) {
      return {'weekday_days': 0, 'weekend_days': 0};
    }
  }

  // ── 回顾：个人最佳 ──

  /// 获取个人最佳记录
  Future<Map<String, dynamic>> getPersonalBests() async {
    try {
      final db = await LocalDb().database;

      // 最高单日工作
      final bestDay = await db.rawQuery('''
        SELECT substr(started_at, 1, 10) as date,
               SUM(duration_seconds) as total
        FROM reminder_sessions
        WHERE type = 'work' AND ended_at IS NOT NULL
        GROUP BY substr(started_at, 1, 10)
        ORDER BY total DESC LIMIT 1
      ''');

      // 最长不跳过
      final streakRows = await db.rawQuery('''
        SELECT skipped, substr(started_at, 1, 10) as date
        FROM reminder_sessions
        WHERE type = 'rest' AND ended_at IS NOT NULL
        ORDER BY started_at ASC
      ''');

      int maxStreak = 0;
      String? streakDate;
      int current = 0;
      String? currentDate;
      for (final row in streakRows) {
        if ((row['skipped'] as int?) == 0) {
          if (current == 0) currentDate = row['date'] as String?;
          current++;
          if (current > maxStreak) {
            maxStreak = current;
            streakDate = currentDate;
          }
        } else {
          current = 0;
          currentDate = null;
        }
      }

      // 最低跳过率日
      final lowSkip = await db.rawQuery('''
        SELECT substr(started_at, 1, 10) as date,
               SUM(CASE WHEN skipped != 0 THEN 1 ELSE 0 END) as skips,
               COUNT(*) as total
        FROM reminder_sessions
        WHERE type = 'rest' AND ended_at IS NOT NULL
        GROUP BY substr(started_at, 1, 10)
        HAVING total > 0
        ORDER BY CAST(skips AS REAL) / total ASC LIMIT 1
      ''');

      return {
        'best_work_day': bestDay.isNotEmpty ? bestDay.first['date'] : null,
        'best_work_seconds': bestDay.isNotEmpty ? (bestDay.first['total'] as int?) ?? 0 : 0,
        'longest_streak': maxStreak,
        'streak_date': streakDate,
        'best_skip_day': lowSkip.isNotEmpty ? lowSkip.first['date'] : null,
        'best_skip_rate': lowSkip.isNotEmpty && (lowSkip.first['total'] as int?)! > 0
            ? ((lowSkip.first['skips'] as int?)! / (lowSkip.first['total'] as int?)!).toStringAsFixed(2)
            : null,
      };
    } catch (e) {
      return {'best_work_seconds': 0, 'longest_streak': 0};
    }
  }
  // ── 同步队列 ──

  /// 获取未同步的会话记录
  Future<List<Map<String, dynamic>>> getPendingSync({int limit = 50}) async {
    try {
      final db = await LocalDb().database;
      return await db.query(
        'reminder_sessions',
        where: 'synced = 0 AND ended_at IS NOT NULL',
        orderBy: 'id ASC',
        limit: limit,
      );
    } catch (e) {
      return [];
    }
  }

  /// 标记已同步
  Future<void> markSynced(int localId, int serverId) async {
    try {
      final db = await LocalDb().database;
      await db.update(
        'reminder_sessions',
        {'synced': 1, 'server_id': serverId},
        where: 'id = ?',
        whereArgs: [localId],
      );
    } catch (e) {
      // 表不存在时忽略
    }
  }

  /// 获取未同步记录数
  Future<int> getPendingCount() async {
    try {
      final db = await LocalDb().database;
      final result = await db.rawQuery(
          'SELECT COUNT(*) as count FROM reminder_sessions WHERE synced = 0 AND ended_at IS NOT NULL');
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }
}
