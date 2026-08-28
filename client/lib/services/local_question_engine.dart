import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/dimension.dart';
import '../utils/local_time_boundary.dart';

/// Local Data Mode 的规则提问引擎。
///
/// 事实 → 问题，不评价用户，也不直接给行动指令。
class LocalQuestionEngine {
  static const _historyKey = 'local_question_history';
  final DateTime Function() _now;

  LocalQuestionEngine({DateTime Function()? now}) : _now = now ?? DateTime.now;

  Future<List<Map<String, dynamic>>> generate(Database db) async {
    final recentIds = await _recentQuestionIds();
    final rules = <Future<Map<String, dynamic>?> Function()>[
      () => _habitStreak(db),
      () => _frequencyChange(db),
      () => _taskBacklog(db),
      () => _completionRate(db),
      () => _timePreference(db),
      () => _focusImbalance(db),
      () => _newHabitStruggle(db),
      () => _quietDay(db),
    ];

    final questions = <Map<String, dynamic>>[];
    for (final rule in rules) {
      if (questions.length >= 2) break;
      final question = await rule();
      if (question == null) continue;
      final id = question['id'] as String;
      if (recentIds.contains(id)) continue;
      questions.add(question);
    }
    await _saveHistory(questions);
    return questions;
  }

  Future<Map<String, dynamic>?> _habitStreak(Database db) async {
    final habits = await db.query(
      'habits',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at ASC',
    );
    final now = _now();
    for (final habit in habits) {
      final habitId = habit['id'] as int;
      final logs = await db.query(
        'habit_logs',
        columns: ['date'],
        where: 'habit_id = ?',
        whereArgs: [habitId],
        orderBy: 'date DESC',
        limit: 1,
      );
      if (logs.isEmpty) continue;
      final last = DateTime.tryParse(logs.first['date'] as String? ?? '');
      if (last == null) continue;
      final days = LocalTimeBoundary.dayStart(now)
          .difference(LocalTimeBoundary.dayStart(last))
          .inDays;
      if (days >= 3 && days <= 30) {
        final name = habit['name'] as String? ?? '';
        return _q(
          'habit_streak_$habitId',
          '「$name」最近一次记录是 $days 天前。那几天发生了什么？',
          'habit_streak',
        );
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _frequencyChange(Database db) async {
    final now = _now();
    final thisMonth = DateTime(now.year, now.month, 1);
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final thisCount = await _countHabitLogsByDate(
      db,
      LocalTimeBoundary.dateKey(thisMonth),
      LocalTimeBoundary.dateKey(nextMonth),
    );
    final lastCount = await _countHabitLogsByDate(
      db,
      LocalTimeBoundary.dateKey(lastMonth),
      LocalTimeBoundary.dateKey(thisMonth),
    );
    if (lastCount > 0 && thisCount < lastCount) {
      return _q(
        'freq_change_monthly',
        '这个月目前记录了 $thisCount 次习惯，上个月共有 $lastCount 次。你觉得差异主要来自什么？',
        'frequency_change',
      );
    }
    return null;
  }

  Future<Map<String, dynamic>?> _taskBacklog(Database db) async {
    final cutoff = _now().subtract(const Duration(days: 7)).toUtc().toIso8601String();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM tasks '
      'WHERE deleted_at IS NULL AND is_completed = 0 AND created_at < ?',
      [cutoff],
    );
    final count = _count(rows);
    if (count >= 3) {
      return _q(
        'task_backlog_7d',
        '有 $count 个任务创建超过 7 天仍未完成。它们现在还重要吗？',
        'task_backlog',
      );
    }
    return null;
  }

  Future<Map<String, dynamic>?> _completionRate(Database db) async {
    final weekStart = LocalTimeBoundary.weekStart(_now());
    final start = weekStart.toUtc().toIso8601String();
    final createdRows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM tasks '
      'WHERE deleted_at IS NULL AND created_at >= ?',
      [start],
    );
    final completedRows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM tasks WHERE deleted_at IS NULL '
      'AND created_at >= ? AND is_completed = 1',
      [start],
    );
    final created = _count(createdRows);
    final completed = _count(completedRows);
    if (created >= 5 && completed * 2 < created) {
      return _q(
        'completion_rate_weekly',
        '本周创建了 $created 个任务，其中 $completed 个目前已完成。和你预期的一样吗？',
        'completion_rate',
      );
    }
    return null;
  }

  Future<Map<String, dynamic>?> _timePreference(Database db) async {
    final cutoff = _now().subtract(const Duration(days: 30)).toUtc().toIso8601String();
    final logs = await db.query(
      'habit_logs',
      columns: ['created_at'],
      where: 'created_at >= ?',
      whereArgs: [cutoff],
    );
    if (logs.length < 10) return null;

    var morning = 0;
    var evening = 0;
    for (final log in logs) {
      final time = LocalTimeBoundary.parseInstant(log['created_at']);
      if (time == null) continue;
      if (time.hour >= 6 && time.hour < 12) morning++;
      if (time.hour >= 20 && time.hour < 24) evening++;
    }
    final morningRate = morning * 100 / logs.length;
    final eveningRate = evening * 100 / logs.length;
    if (morning > 0 && evening > 0 && morningRate > 60 && eveningRate < 30) {
      return _q(
        'time_preference',
        '过去 30 天，上午记录约占 ${morningRate.round()}%，晚上约占 ${eveningRate.round()}%。这个时间分布符合你的实际感受吗？',
        'time_preference',
      );
    }
    return null;
  }

  Future<Map<String, dynamic>?> _focusImbalance(Database db) async {
    if (!await _tableExists(db, 'behavior_events')) return null;
    final cutoff = _now().subtract(const Duration(days: 7)).toUtc().toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT st.dimension_key AS dimension_key, SUM(be.duration_min) AS minutes
      FROM behavior_events be
      INNER JOIN system_tags st ON st.id = be.system_tag_id
      WHERE be.is_deleted = 0
        AND be.event_type = 'session_ended'
        AND st.dimension_key != ''
        AND be.occurred_at >= ?
      GROUP BY st.dimension_key
      ''',
      [cutoff],
    );
    final minutes = <String, int>{};
    for (final row in rows) {
      final key = row['dimension_key'] as String?;
      if (key != null) minutes[key] = row['minutes'] as int? ?? 0;
    }
    for (final dimension in DimensionCatalog.all) {
      if ((minutes[dimension.keyValue] ?? 0) == 0) {
        return _q(
          'focus_imbalance_${dimension.keyValue}',
          '过去 7 天，「${dimension.icon}${dimension.name}」维度没有专注记录。这是有意的安排吗？',
          'focus_imbalance',
        );
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _newHabitStruggle(Database db) async {
    final now = _now();
    final cutoff = now.subtract(const Duration(days: 14)).toUtc().toIso8601String();
    final habits = await db.query(
      'habits',
      where: 'deleted_at IS NULL AND created_at >= ?',
      whereArgs: [cutoff],
      orderBy: 'created_at ASC',
    );
    for (final habit in habits) {
      final createdAt = LocalTimeBoundary.parseInstant(habit['created_at']);
      if (createdAt == null) continue;
      final days = now.difference(createdAt).inDays;
      if (days < 3) continue;
      final habitId = habit['id'] as int;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM habit_logs WHERE habit_id = ?',
        [habitId],
      );
      final count = _count(rows);
      if (count <= 1) {
        final name = habit['name'] as String? ?? '';
        return _q(
          'new_habit_$habitId',
          '「$name」创建 $days 天，目前记录 $count 次。当时是什么让你没有继续？',
          'new_habit_struggle',
        );
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _quietDay(Database db) async {
    final now = _now();
    if (now.hour < 20) return null;
    final today = LocalTimeBoundary.dayStart(now);
    final range = LocalTimeBoundary.dayRange(today);
    final date = LocalTimeBoundary.dateKey(today);
    final taskRows = await db.rawQuery(
      '''SELECT COUNT(*) AS cnt FROM tasks
         WHERE deleted_at IS NULL AND (
           (created_at >= ? AND created_at < ?) OR
           (is_completed = 1 AND completed_at >= ? AND completed_at < ?)
         )''',
      [range.startUtc, range.endUtc, range.startUtc, range.endUtc],
    );
    final habitRows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM habit_logs WHERE date = ?',
      [date],
    );
    var sessionCount = 0;
    if (await _tableExists(db, 'behavior_events')) {
      final eventRows = await db.rawQuery(
        '''SELECT COUNT(*) AS cnt FROM behavior_events
           WHERE is_deleted = 0 AND event_type = 'session_ended'
             AND occurred_at >= ? AND occurred_at < ?''',
        [range.startUtc, range.endUtc],
      );
      sessionCount = _count(eventRows);
    }
    if (_count(taskRows) == 0 && _count(habitRows) == 0 && sessionCount == 0) {
      return _q(
        'quiet_day',
        '今天还没有记录到任务、习惯或专注活动。今天和往常有什么不同？',
        'quiet_day',
      );
    }
    return null;
  }

  Map<String, dynamic> _q(String id, String content, String type) => {
        'id': id,
        'content': content,
        'type': type,
      };

  Future<int> _countHabitLogsByDate(Database db, String start, String end) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM habit_logs WHERE date >= ? AND date < ?',
      [start, end],
    );
    return _count(rows);
  }

  int _count(List<Map<String, Object?>> rows) =>
      rows.isEmpty ? 0 : (rows.first['cnt'] as int? ?? 0);

  Future<bool> _tableExists(Database db, String name) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [name],
    );
    return rows.isNotEmpty;
  }

  Future<Set<String>> _recentQuestionIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final cutoff = _now().subtract(const Duration(days: 7));
      return decoded
          .whereType<Map<String, dynamic>>()
          .where((item) {
            final askedAt = DateTime.tryParse(item['asked_at'] as String? ?? '');
            return askedAt != null && askedAt.toLocal().isAfter(cutoff);
          })
          .map((item) => item['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _saveHistory(List<Map<String, dynamic>> questions) async {
    if (questions.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    final history = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        history.addAll(decoded.whereType<Map<String, dynamic>>());
      } catch (_) {}
    }
    final cutoff = _now().subtract(const Duration(days: 30));
    history.removeWhere((item) {
      final askedAt = DateTime.tryParse(item['asked_at'] as String? ?? '');
      return askedAt == null || askedAt.toLocal().isBefore(cutoff);
    });
    final askedAt = _now().toUtc().toIso8601String();
    for (final question in questions) {
      history.add({'id': question['id'], 'asked_at': askedAt});
    }
    await prefs.setString(_historyKey, jsonEncode(history));
  }
}
