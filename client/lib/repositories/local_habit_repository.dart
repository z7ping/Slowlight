import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import '../db/local_db.dart';
import '../models/habit_occurrence.dart';
import '../models/habit_schedule_rule.dart';

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
    var rows = await db.query(
      'habit_logs',
      where: 'habit_id = ? AND date = ?',
      whereArgs: [habitId, _dateStr(cursor)],
      limit: 1,
    );
    if (rows.isEmpty) cursor = cursor.subtract(const Duration(days: 1));

    var streak = 0;
    while (true) {
      rows = await db.query(
        'habit_logs',
        where: 'habit_id = ? AND date = ?',
        whereArgs: [habitId, _dateStr(cursor)],
        limit: 1,
      );
      if (rows.isEmpty) break;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
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
      final rule = HabitOccurrence.rule(mutable['schedule_rule'],
        legacyFrequency: mutable['frequency']?.toString() ?? 'daily');
      if (rule != null) {
        try {
          final occurrence = HabitOccurrence.calculate(rule, now,
            requestKey: 'event:probe-availability');
          if (occurrence.periodStart != null) {
            final countRows = await db.rawQuery(
              'SELECT COUNT(*) AS total FROM habit_logs WHERE habit_id = ? AND date >= ? AND date < ?',
              [hid, occurrence.periodStart, occurrence.periodEnd],
            );
            final count = countRows.first['total'] as int? ?? 0;
            mutable['period_count'] = count;
            mutable['period_target'] = occurrence.target;
            mutable['can_check_in'] = count < occurrence.target &&
              (occurrence.sameDayMultiple || todayRows.isEmpty);
          } else {
            final prior = await db.query('habit_logs',
              where:'habit_id = ? AND occurrence_key = ?',
              whereArgs:[hid, occurrence.key],limit:1);
            mutable['can_check_in'] = prior.isEmpty;
          }
        } catch (_) { mutable['can_check_in'] = false; }
      }
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
    Map<String, dynamic>? scheduleRule,
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
      'schedule_rule': _encodeJson(scheduleRule ?? const {}),
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
    Map<String, dynamic>? scheduleRule,
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
    if (scheduleRule != null) updates['schedule_rule'] = _encodeJson(scheduleRule);
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
    String? period,
    String? occurrenceKey,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final day = date ?? _dateStr(now);
    final habit = await getById(habitId);
    if (habit == null) throw StateError('习惯不存在');
    final rule = HabitOccurrence.rule(habit['schedule_rule'],
        legacyFrequency: habit['frequency']?.toString() ?? 'daily');
    if (date != null && DateTime.tryParse(date)?.isAfter(DateTime(now.year, now.month, now.day)) == true) {
      throw StateError('不能记录未来日期');
    }
    if (rule != null && date != null) {
      final created = DateTime.tryParse(habit['created_at']?.toString() ?? '')?.toLocal();
      if (created != null &&
          DateTime.parse(day).isBefore(DateTime(created.year,created.month,created.day))) {
        throw StateError('打卡日期早于习惯创建日期');
      }
    }
    final event = rule == null ? null : HabitOccurrence.calculate(
        rule, now, date: day, requestKey: occurrenceKey);
    return db.transaction((tx) async {
      final existing = await tx.query('habit_logs',
        where: rule == null ? 'habit_id = ? AND date = ?' :
            'habit_id = ? AND occurrence_key = ?',
        whereArgs: [habitId, rule == null ? day : event!.key],
        limit: 1);
      if (existing.isNotEmpty) {
        return {'message': '该时段已记录', 'already_checked': true,
          'log': existing.first, 'streak_count': habit['streak_count'] ?? 0};
      }
      if (event?.periodStart != null) {
        final counts = await tx.rawQuery(
          'SELECT COUNT(*) AS total FROM habit_logs WHERE habit_id = ? AND date >= ? AND date < ?',
          [habitId, event!.periodStart, event.periodEnd]);
        final count = counts.first['total'] as int? ?? 0;
        if (count >= event.target) throw StateError('本周期已完成目标次数');
        if (!event.sameDayMultiple) {
          final sameDay = await tx.query('habit_logs',
            where: 'habit_id = ? AND date = ?',whereArgs:[habitId,day],limit:1);
          if (sameDay.isNotEmpty) return {'message':'该日已记录',
            'already_checked':true,'log':sameDay.first};
        }
      }
      final at = date == null ? now :
          DateTime(DateTime.parse(day).year,DateTime.parse(day).month,DateTime.parse(day).day,12);
      final actualPeriod = period?.isNotEmpty == true
          ? period! : habit['preferred_period']?.toString() ?? '';
      final actualDuration = durationMin ?? habit['duration_min'] as int? ?? 0;
      final createdAt = _nowUtc();
      final id = await tx.insert('habit_logs', {
        'habit_id':habitId, 'date':day, 'occurrence_key':event?.key,
        'occurred_at':at.toUtc().toIso8601String(), 'period':actualPeriod,
        'duration_min':actualDuration,'note':note,'created_at':createdAt,
      });
      final streak = rule == null
          ? await _calculateCurrentStreak(tx,habitId,now) : 0;
      await tx.update('habits',
        {'streak_count':streak,'updated_at':_nowUtc()},
        where:'id = ?',whereArgs:[habitId]);
      return {'message':'打卡成功','log':{
        'id':id,'habit_id':habitId,'date':day,'occurrence_key':event?.key,
        'occurred_at':at.toUtc().toIso8601String(),
        'period':actualPeriod,'duration_min':actualDuration,
        'note':note,'created_at':createdAt,
      },'streak_count':streak};
    });
  }

  Future<Map<String, dynamic>> uncheckIn(int habitId) async {
    final db = await _db.database;
    final localNow = DateTime.now();
    final todayStr = _dateStr(localNow);
    final existing = await db.query(
      'habit_logs',
      where: 'habit_id = ? AND date = ?',
      whereArgs: [habitId, todayStr],
      orderBy: 'created_at DESC, id DESC',
      limit: 1,
    );
    if (existing.isEmpty) throw Exception('今日未打卡，无法取消');

    await db.delete('habit_logs',where:'id = ?',whereArgs:[existing.first['id']]);
    final habit = await getById(habitId);
    final rule = HabitOccurrence.rule(habit?['schedule_rule']);
    final streak = rule == null ? await _calculateCurrentStreak(db, habitId, localNow) : 0;
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

  Future<Map<String, dynamic>> updateLog(
    int habitId,
    int logId,
    Map<String, dynamic> data,
  ) async {
    final db = await _db.database;
    final allowed = <String, dynamic>{};
    for (final key in ['note', 'duration_min', 'period']) {
      if (data.containsKey(key)) allowed[key] = data[key];
    }
    if (allowed.isEmpty) throw Exception('没有可更新字段');
    if (allowed['duration_min'] is int &&
        (allowed['duration_min'] as int) < 0) {
      throw Exception('duration_min 不能为负数');
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
