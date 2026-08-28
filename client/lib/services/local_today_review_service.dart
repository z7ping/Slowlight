import 'package:sqflite/sqflite.dart';

import '../db/local_db.dart';
import '../utils/local_time_boundary.dart';
import 'local_question_engine.dart';

/// Local Data Mode 下的今日回顾计算。
///
/// “今天”按设备本地日历定义，但 instant 全部用 UTC 边界查询；HabitLog.date
/// 是纯日历日期，继续使用 YYYY-MM-DD。
class LocalTodayReviewService {
  static final LocalTodayReviewService _instance =
      LocalTodayReviewService._internal();

  factory LocalTodayReviewService() => _instance;
  LocalTodayReviewService._internal();

  Future<Map<String, dynamic>> computeTodayReview() async {
    final db = await LocalDb().database;
    final today = LocalTimeBoundary.dayStart(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final todayDate = LocalTimeBoundary.dateKey(today);
    final yesterdayDate = LocalTimeBoundary.dateKey(yesterday);
    final weekAgoDate = LocalTimeBoundary.dateKey(weekAgo);

    final todayCompletedTasks = await _completedTasksForDay(db, today);
    final taskCompleted = todayCompletedTasks.length;
    final taskCreated = await _countTasksCreated(db, today);
    final yesterdayTaskCompleted = await _countTasksCompleted(db, yesterday);
    final weekAgoTaskCompleted = await _countTasksCompleted(db, weekAgo);

    final habitTotal = await _countActiveHabits(db);
    final habitChecked = await _countHabitLogs(db, todayDate);
    final yesterdayHabitChecked = await _countHabitLogs(db, yesterdayDate);
    final weekAgoHabitChecked = await _countHabitLogs(db, weekAgoDate);

    final todayFocus = await _focusForDay(db, today);
    final yesterdayFocus = await _focusForDay(db, yesterday);
    final weekAgoFocus = await _focusForDay(db, weekAgo);
    final questions = await LocalQuestionEngine().generate(db);

    return {
      'facts': {
        'habit_checked': habitChecked,
        'habit_total': habitTotal,
        'task_completed': taskCompleted,
        'task_created': taskCreated,
        'focus_minutes': todayFocus.minutes,
        'focus_count': todayFocus.count,
        'tag_distribution': todayFocus.tagDistribution,
        'today_completed_tasks': todayCompletedTasks.map(_taskToJson).toList(),
      },
      'patterns': {
        'habit_delta': habitChecked - yesterdayHabitChecked,
        'task_delta': taskCompleted - yesterdayTaskCompleted,
        'focus_delta': todayFocus.minutes - yesterdayFocus.minutes,
        'habit_week_delta': habitChecked - weekAgoHabitChecked,
        'task_week_delta': taskCompleted - weekAgoTaskCompleted,
        'focus_week_delta': todayFocus.minutes - weekAgoFocus.minutes,
      },
      'questions': questions,
    };
  }

  Future<List<Map<String, Object?>>> _completedTasksForDay(
    Database db,
    DateTime day,
  ) async {
    final range = LocalTimeBoundary.dayRange(day);
    return db.rawQuery(
      '''
      SELECT t.*, l.name AS list_name
      FROM tasks t
      LEFT JOIN lists l ON t.list_id = l.id
      WHERE t.deleted_at IS NULL
        AND t.is_completed = 1
        AND t.completed_at >= ?
        AND t.completed_at < ?
      ORDER BY t.completed_at DESC
      ''',
      [range.startUtc, range.endUtc],
    );
  }

  Future<int> _countActiveHabits(Database db) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM habits WHERE deleted_at IS NULL',
    );
    return _count(rows);
  }

  Future<int> _countHabitLogs(Database db, String date) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS cnt
      FROM habit_logs hl
      INNER JOIN habits h ON h.id = hl.habit_id
      WHERE h.deleted_at IS NULL AND hl.date = ?
      ''',
      [date],
    );
    return _count(rows);
  }

  Future<int> _countTasksCreated(Database db, DateTime day) async {
    final range = LocalTimeBoundary.dayRange(day);
    final rows = await db.rawQuery(
      '''SELECT COUNT(*) AS cnt FROM tasks
         WHERE deleted_at IS NULL AND created_at >= ? AND created_at < ?''',
      [range.startUtc, range.endUtc],
    );
    return _count(rows);
  }

  Future<int> _countTasksCompleted(Database db, DateTime day) async {
    final range = LocalTimeBoundary.dayRange(day);
    final rows = await db.rawQuery(
      '''SELECT COUNT(*) AS cnt FROM tasks
         WHERE deleted_at IS NULL AND is_completed = 1
           AND completed_at >= ? AND completed_at < ?''',
      [range.startUtc, range.endUtc],
    );
    return _count(rows);
  }

  Future<_FocusSnapshot> _focusForDay(Database db, DateTime day) async {
    if (await _tableExists(db, 'behavior_events')) {
      return _focusFromBehaviorEvents(db, day);
    }
    if (await _tableExists(db, 'work_sessions')) {
      return _focusFromWorkSessions(db, day);
    }
    return const _FocusSnapshot.empty();
  }

  Future<_FocusSnapshot> _focusFromBehaviorEvents(
    Database db,
    DateTime day,
  ) async {
    final range = LocalTimeBoundary.dayRange(day);
    final rows = await db.query(
      'behavior_events',
      where: "is_deleted = 0 AND event_type = 'session_ended' "
          'AND occurred_at >= ? AND occurred_at < ?',
      whereArgs: [range.startUtc, range.endUtc],
      orderBy: 'occurred_at ASC',
    );
    return _buildFocusSnapshot(
      db,
      rows,
      durationMinutes: (row) => row['duration_min'] as int? ?? 0,
    );
  }

  Future<_FocusSnapshot> _focusFromWorkSessions(
    Database db,
    DateTime day,
  ) async {
    final range = LocalTimeBoundary.dayRange(day);
    final rows = await db.query(
      'work_sessions',
      where: "session_type = 'work' AND ended_at IS NOT NULL "
          'AND ended_at >= ? AND ended_at < ?',
      whereArgs: [range.startUtc, range.endUtc],
      orderBy: 'ended_at ASC',
    );
    return _buildFocusSnapshot(
      db,
      rows,
      durationMinutes: (row) {
        final seconds = row['duration_sec'] as int? ?? 0;
        final minutes = seconds ~/ 60;
        return minutes < 1 ? 1 : minutes;
      },
    );
  }

  Future<_FocusSnapshot> _buildFocusSnapshot(
    Database db,
    List<Map<String, Object?>> rows, {
    required int Function(Map<String, Object?> row) durationMinutes,
  }) async {
    final tagRows = await db.query('system_tags');
    final tags = <int, Map<String, Object?>>{};
    for (final row in tagRows) {
      final id = row['id'];
      if (id is int) tags[id] = row;
    }

    var focusMinutes = 0;
    var focusCount = 0;
    final minutesByTag = <int, int>{};

    for (final row in rows) {
      final minutes = durationMinutes(row);
      focusMinutes += minutes;
      focusCount++;
      final systemTagId = row['system_tag_id'] as int?;
      if (systemTagId != null) {
        minutesByTag[systemTagId] = (minutesByTag[systemTagId] ?? 0) + minutes;
      }
    }

    final tagDistribution = minutesByTag.entries.map((entry) {
      final tag = tags[entry.key];
      return <String, dynamic>{
        'tag_id': entry.key,
        'name': tag?['name'] as String? ?? '',
        'icon': tag?['icon'] as String? ?? '',
        'minutes': entry.value,
      };
    }).toList()
      ..sort((a, b) =>
          (b['minutes'] as int).compareTo(a['minutes'] as int));

    return _FocusSnapshot(
      minutes: focusMinutes,
      count: focusCount,
      tagDistribution: tagDistribution,
    );
  }

  Future<bool> _tableExists(Database db, String tableName) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [tableName],
    );
    return rows.isNotEmpty;
  }

  int _count(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return 0;
    return rows.first['cnt'] as int? ?? 0;
  }

  Map<String, dynamic> _taskToJson(Map<String, Object?> row) {
    final parsed = LocalTimeBoundary.parseInstant(row['completed_at']);
    final completedAt = parsed == null
        ? ''
        : '${parsed.hour.toString().padLeft(2, '0')}:'
            '${parsed.minute.toString().padLeft(2, '0')}';
    return {
      'id': row['id'],
      'title': row['title'],
      'list_name': row['list_name'] as String? ?? '',
      'task_type': row['task_type'] as String? ?? 'daily',
      'output_level': row['output_level'] as String? ?? '',
      'completed_at': completedAt,
      'is_milestone': (row['is_milestone'] as int? ?? 0) == 1,
    };
  }
}

class _FocusSnapshot {
  final int minutes;
  final int count;
  final List<Map<String, dynamic>> tagDistribution;

  const _FocusSnapshot({
    required this.minutes,
    required this.count,
    required this.tagDistribution,
  });

  const _FocusSnapshot.empty()
      : minutes = 0,
        count = 0,
        tagDistribution = const [];
}
