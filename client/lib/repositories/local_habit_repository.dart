import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import '../db/local_db.dart';
import '../models/habit_goal_progress.dart';
import '../utils/habit_record_key.dart';

/// 本地习惯仓储（SQLite 内部实现）。
/// HabitLog.date 是日历日期；created_at/updated_at 等 instant 统一存 UTC。
class LocalHabitRepository {
  final _db = LocalDb();

  String _dateStr(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _nowUtc() => DateTime.now().toUtc().toIso8601String();

  Future<int> _calculateCurrentStreak(
    Database db,
    int habitId,
    DateTime now,
  ) async {
    var cursor = DateTime(now.year, now.month, now.day);
    final habit = (await db.query('habits',
      where: 'id = ?', whereArgs: [habitId], limit: 1)).first;
    Future<bool> met(DateTime date) async {
      final rows = await db.query('habit_logs',
        where: 'habit_id = ? AND date = ?',
        whereArgs: [habitId, _dateStr(date)]);
      if ((habit['goal_period'] == 'day') &&
          ((habit['goal_value'] as int? ?? 0) > 0)) {
        return HabitGoalProgress.met(habit,
          HabitGoalProgress.current(habit, rows, now: date));
      }
      return rows.isNotEmpty;
    }
    if (!await met(cursor)) cursor = cursor.subtract(const Duration(days: 1));
    var streak = 0;
    while (await met(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
      if (streak >= 36500) break;
    }
    return streak;
  }

  Future<List<Map<String, dynamic>>> getAll() async {
    final db = await _db.database;
    final maps = await db.query(
      'habits',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at ASC',
    );

    final now = DateTime.now();
    final todayStr = _dateStr(now);
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final weekStartStr = _dateStr(weekStart);

    final enriched = <Map<String, dynamic>>[];
    for (final habit in maps) {
      final mutable = Map<String, dynamic>.from(habit);
      final hid = mutable['id'] as int;
      final todayRows = await db.query(
        'habit_logs',
        where: 'habit_id = ? AND date = ?',
        whereArgs: [hid, todayStr],
        limit: 1,
      );
      mutable['checked_today'] = todayRows.isNotEmpty;
      final weekRows = await db.query(
        'habit_logs',
        where: 'habit_id = ? AND date >= ? AND date <= ?',
        whereArgs: [hid, weekStartStr, todayStr],
      );
      mutable['checked_days'] =
          weekRows.map((row) => row['date'] as String).toSet().toList();
      final monthStart = _dateStr(DateTime(now.year, now.month, 1));
      final goalLogs = await db.query('habit_logs',
          where: 'habit_id = ? AND date >= ? AND date <= ?',
          whereArgs: [hid, monthStart.compareTo(weekStartStr) < 0 ? monthStart : weekStartStr, todayStr]);
      final progress = HabitGoalProgress.current(mutable, goalLogs, now: now);
      mutable['goal_progress'] = progress;
      mutable['goal_met'] = HabitGoalProgress.met(mutable, progress);
      enriched.add(mutable);
    }
    return enriched;
  }

  Future<Map<String, dynamic>?> getById(int id) async {
    final db = await _db.database;
    final maps = await db.query(
      'habits',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Map<String, dynamic>.from(maps.first);
  }

  Future<Map<String, dynamic>> create({
    required String name,
    String icon = '✅',
    String color = '#52c41a',
    String frequency = 'daily',
    String recordType = 'check',
    String recordUnit = '次',
    String recordTimeLabel = '',
    bool allowMultiplePerDay = false,
    String goalPeriod = 'none',
    String goalMetric = 'events',
    int goalValue = 0,
    int targetDays = 0,
    int? systemTagId,
    String preferredPeriod = '',
    int durationMin = 0,
    bool generateTask = false,
    bool showCheckinDialog = false,
    String specificTime = '',
    Map<String, dynamic>? reminderAt,
  }) async {
    final db = await _db.database;
    final now = _nowUtc();
    final id = await db.insert('habits', {
      'name': name,
      'icon': icon,
      'color': color,
      'frequency': frequency,
      'record_type': recordType,
      'record_unit': recordUnit,
      'record_time_label': recordTimeLabel,
      'allow_multiple_per_day': allowMultiplePerDay ? 1 : 0,
      'goal_period': goalPeriod,
      'goal_metric': goalMetric,
      'goal_value': goalValue,
      'target_days': targetDays,
      'system_tag_id': systemTagId,
      'preferred_period': preferredPeriod,
      'duration_min': durationMin,
      'generate_task': generateTask ? 1 : 0,
      'show_checkin_dialog': showCheckinDialog ? 1 : 0,
      'specific_time': specificTime,
      'reminder_at': reminderAt != null ? _encodeJson(reminderAt) : '{}',
      'created_at': now,
      'updated_at': now,
    });
    final result = await getById(id);
    if (result == null) throw Exception('创建习惯失败');
    return result;
  }

  Future<Map<String, dynamic>> update(
    int id, {
    String? name,
    String? icon,
    String? color,
    String? frequency,
    String? recordType,
    String? recordUnit,
    String? recordTimeLabel,
    bool? allowMultiplePerDay,
    String? goalPeriod,
    String? goalMetric,
    int? goalValue,
    int? targetDays,
    int? systemTagId,
    bool setSystemTag = false,
    String? preferredPeriod,
    int? durationMin,
    bool? generateTask,
    bool? showCheckinDialog,
    String? specificTime,
    Map<String, dynamic>? reminderAt,
  }) async {
    final db = await _db.database;
    final updates = <String, dynamic>{'updated_at': _nowUtc()};
    if (name != null) updates['name'] = name;
    if (icon != null) updates['icon'] = icon;
    if (color != null) updates['color'] = color;
    if (frequency != null) updates['frequency'] = frequency;
    if (recordType != null) updates['record_type'] = recordType;
    if (recordUnit != null) updates['record_unit'] = recordUnit;
    if (recordTimeLabel != null) updates['record_time_label'] = recordTimeLabel;
    if (allowMultiplePerDay != null) updates['allow_multiple_per_day'] = allowMultiplePerDay ? 1 : 0;
    if (goalPeriod != null) updates['goal_period'] = goalPeriod;
    if (goalMetric != null) updates['goal_metric'] = goalMetric;
    if (goalValue != null) updates['goal_value'] = goalValue;
    if (targetDays != null) updates['target_days'] = targetDays;
    if (setSystemTag) updates['system_tag_id'] = systemTagId;
    if (preferredPeriod != null) updates['preferred_period'] = preferredPeriod;
    if (durationMin != null) updates['duration_min'] = durationMin;
    if (generateTask != null) updates['generate_task'] = generateTask ? 1 : 0;
    if (showCheckinDialog != null) {
      updates['show_checkin_dialog'] = showCheckinDialog ? 1 : 0;
    }
    if (specificTime != null) updates['specific_time'] = specificTime;
    if (reminderAt != null) updates['reminder_at'] = _encodeJson(reminderAt);

    await db.update('habits', updates, where: 'id = ?', whereArgs: [id]);
    final result = await getById(id);
    if (result == null) throw Exception('更新习惯失败');
    return result;
  }

  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.update(
      'habits',
      {'deleted_at': _nowUtc()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>> checkIn(
    int habitId, {
    String note = '',
    String? date,
    int? durationMin,
    int? countValue,
    String? occurredAt,
    String? period,
    String? clientKey,
  }) async {
    final db = await _db.database;
    final localNow = DateTime.now();
    final checkDate = date ?? _dateStr(localNow);
    final habit = await getById(habitId);
    if (habit == null) throw Exception('习惯不存在');

    final effectiveKey = clientKey ?? createHabitRecordKey();
    final replay = await db.query('habit_logs',
        where: 'client_key = ?', whereArgs: [effectiveKey], limit: 1);
    if (replay.isNotEmpty) return {'log': replay.first, 'already_checked': true};
    final existing = await db.query(
      'habit_logs',
      where: 'habit_id = ? AND date = ?',
      whereArgs: [habitId, checkDate],
      limit: 1,
    );
    if (habit['allow_multiple_per_day'] != 1 && existing.isNotEmpty) {
      return {
        'message': '该日期已打卡',
        'already_checked': true,
        'log': existing.first,
        'streak_count': habit['streak_count'] as int? ?? 0,
      };
    }

    final recordType = habit['record_type'] as String? ?? 'legacy';
    final actualPeriod = recordType == 'legacy' || recordType == 'duration'
        ? (period?.isNotEmpty == true
            ? period!
            : (habit['preferred_period'] as String? ?? ''))
        : '';
    final actualDuration = recordType == 'legacy' || recordType == 'duration'
        ? (durationMin ?? (habit['duration_min'] as int? ?? 0)) : 0;
    if (actualDuration < 0) throw ArgumentError('时长不能为负数');
    if (recordType == 'count' && (countValue == null || countValue <= 0)) {
      throw ArgumentError('完成次数必须大于 0');
    }
    DateTime? occurred;
    if (occurredAt != null && occurredAt.isNotEmpty) {
      occurred = DateTime.parse(occurredAt);
      if (occurred.isAfter(localNow) || _dateStr(occurred.toLocal()) != checkDate) {
        throw ArgumentError('实际发生时间与打卡日期不一致');
      }
    } else if (((habit['record_time_label'] as String? ?? '').isNotEmpty ||
        habit['allow_multiple_per_day'] == 1) &&
        checkDate == _dateStr(localNow)) {
      occurred = localNow;
    }
    final actualOccurredAt = occurred?.toUtc().toIso8601String();
    final actualCount = recordType == 'count' ? countValue : null;
    final createdAt = _nowUtc();

    final logId = await db.insert('habit_logs', {
      'habit_id': habitId,
      'date': checkDate,
      'period': actualPeriod,
      'duration_min': actualDuration,
      'count_value': actualCount,
      'occurred_at': actualOccurredAt,
      'client_key': effectiveKey,
      'note': note,
      'created_at': createdAt,
    });

    final streakCount = await _calculateCurrentStreak(db, habitId, localNow);
    await db.update(
      'habits',
      {'streak_count': streakCount, 'updated_at': _nowUtc()},
      where: 'id = ?',
      whereArgs: [habitId],
    );

    return {
      'message': '打卡成功',
      'log': {
        'id': logId,
        'habit_id': habitId,
        'date': checkDate,
        'period': actualPeriod,
        'duration_min': actualDuration,
        'count_value': actualCount,
        'occurred_at': actualOccurredAt,
        'client_key': effectiveKey,
        'note': note,
        'created_at': createdAt,
      },
      'streak_count': streakCount,
    };
  }

  Future<Map<String, dynamic>> uncheckIn(int habitId) async {
    final db = await _db.database;
    final localNow = DateTime.now();
    final todayStr = _dateStr(localNow);
    final existing = await db.query(
      'habit_logs',
      where: 'habit_id = ? AND date = ?',
      whereArgs: [habitId, todayStr],
      limit: 1,
    );
    if (existing.isEmpty) throw Exception('今日未打卡，无法取消');

    if ((await getById(habitId))?['allow_multiple_per_day'] == 1) {
      throw StateError('此习惯允许多次记录，请从详情逐条撤销');
    }
    await db.delete(
      'habit_logs',
      where: 'habit_id = ? AND date = ?',
      whereArgs: [habitId, todayStr],
    );
    final streak = await _calculateCurrentStreak(db, habitId, localNow);
    await db.update(
      'habits',
      {'streak_count': streak, 'updated_at': _nowUtc()},
      where: 'id = ?',
      whereArgs: [habitId],
    );
    return {'message': '取消打卡成功', 'streak_count': streak};
  }

  Future<Map<String, dynamic>> getLogs(int habitId, {String? month}) async {
    final db = await _db.database;
    String where = 'habit_id = ?';
    final whereArgs = <dynamic>[habitId];
    if (month != null) {
      where += ' AND date LIKE ?';
      whereArgs.add('$month%');
    }
    final logs = await db.query(
      'habit_logs',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'date DESC',
    );
    final todayStr = _dateStr(DateTime.now());
    return {
      'logs': logs,
      'stats': {
        'total_days': logs.length,
        'today_checked': logs.any((log) => log['date'] == todayStr),
      },
    };
  }

  Future<void> deleteLog(int habitId, int logId) async {
    final db = await _db.database;
    final deleted = await db.delete('habit_logs',
        where: 'id = ? AND habit_id = ?', whereArgs: [logId, habitId]);
    if (deleted == 0) throw StateError('打卡记录不存在');
    final streak = await _calculateCurrentStreak(db, habitId, DateTime.now());
    await db.update('habits', {
      'streak_count': streak, 'updated_at': _nowUtc(),
    }, where: 'id = ?', whereArgs: [habitId]);
  }

  Future<Map<String, dynamic>> updateLog(
    int habitId,
    int logId,
    Map<String, dynamic> data,
  ) async {
    final db = await _db.database;
    final allowed = <String, dynamic>{};
    for (final key in ['note', 'duration_min', 'count_value', 'occurred_at', 'period']) {
      if (data.containsKey(key)) allowed[key] = data[key];
    }
    if (allowed.isEmpty) throw Exception('没有可更新字段');
    if (allowed['duration_min'] is int &&
        (allowed['duration_min'] as int) < 0) {
      throw Exception('duration_min 不能为负数');
    }
    if (allowed['count_value'] is int && (allowed['count_value'] as int) <= 0) {
      throw ArgumentError('count_value 必须大于 0');
    }
    if (allowed['occurred_at'] is String && (allowed['occurred_at'] as String).isNotEmpty) {
      final occurred = DateTime.parse(allowed['occurred_at'] as String);
      final rows = await db.query('habit_logs', columns: ['date'],
        where: 'id = ? AND habit_id = ?', whereArgs: [logId, habitId], limit: 1);
      if (rows.isEmpty || occurred.isAfter(DateTime.now()) ||
          _dateStr(occurred.toLocal()) != rows.first['date']) {
        throw ArgumentError('实际发生时间不合法');
      }
      allowed['occurred_at'] = occurred.toUtc().toIso8601String();
    }
    final count = await db.update('habit_logs', allowed,
        where: 'id = ? AND habit_id = ?', whereArgs: [logId, habitId]);
    if (count == 0) throw Exception('打卡记录不存在');
    final rows = await db.query('habit_logs',
        where: 'id = ?', whereArgs: [logId], limit: 1);
    return rows.first;
  }

  Future<List<Map<String, dynamic>>> getSystemTags() async {
    final db = await _db.database;
    return db.query('system_tags', orderBy: 'created_at ASC');
  }

  Future<Map<String, dynamic>> createSystemTag({
    required String name,
    required String icon,
    required String color,
  }) async {
    final db = await _db.database;
    final now = _nowUtc();
    final id = await db.insert('system_tags', {
      'name': name,
      'icon': icon,
      'color': color,
      'created_at': now,
      'updated_at': now,
    });
    final result = await db.query(
      'system_tags',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return Map<String, dynamic>.from(result.first);
  }

  Future<Map<String, dynamic>> updateSystemTag(
    int id, {
    String? icon,
    String? color,
  }) async {
    final db = await _db.database;
    final updates = <String, dynamic>{'updated_at': _nowUtc()};
    if (icon != null) updates['icon'] = icon;
    if (color != null) updates['color'] = color;
    await db.update('system_tags', updates, where: 'id = ?', whereArgs: [id]);
    final result = await db.query(
      'system_tags',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return Map<String, dynamic>.from(result.first);
  }

  Future<void> deleteSystemTag(int id) async {
    final db = await _db.database;
    await db.delete('system_tags', where: 'id = ?', whereArgs: [id]);
  }

  String _encodeJson(Map<String, dynamic> map) => jsonEncode(map);
}
