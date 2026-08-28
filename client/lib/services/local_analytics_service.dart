import 'package:sqflite/sqflite.dart';

import '../db/local_db.dart';
import '../db/local_product_core_schema.dart';
import '../models/dimension.dart';
import '../utils/local_time_boundary.dart';

/// Local Data Mode 的统一分析计算。
///
/// instant 使用 UTC 存储/查询；HabitLog.date 保持日历日期；Dimension 固定为
/// 身体/认知/产出/关系，ObservationTag 只作为行为到 Dimension 的映射。
class LocalAnalyticsService {
  static final LocalAnalyticsService _instance = LocalAnalyticsService._();
  factory LocalAnalyticsService() => _instance;
  LocalAnalyticsService._();

  Future<Map<String, dynamic>> getOutputStats({String period = 'all'}) async {
    final db = await LocalDb().database;
    final now = DateTime.now();
    final weekStart = LocalTimeBoundary.weekStart(now);
    final monthStart = LocalTimeBoundary.monthStart(now);
    final periodStart = switch (period) {
      'week' => weekStart,
      'month' => monthStart,
      _ => null,
    };

    var where = "deleted_at IS NULL AND is_completed = 1 AND output_level != ''";
    final args = <Object?>[];
    if (periodStart != null) {
      where += ' AND completed_at >= ?';
      args.add(periodStart.toUtc().toIso8601String());
    }
    final tasks = await db.query('tasks', where: where, whereArgs: args);
    final byLevel = <String, int>{};
    final byTaskType = <String, int>{};
    var milestones = 0;
    for (final task in tasks) {
      final level = task['output_level'] as String? ?? '';
      if (level.isNotEmpty) byLevel[level] = (byLevel[level] ?? 0) + 1;
      final type = task['task_type'] as String? ?? '';
      if (type.isNotEmpty) byTaskType[type] = (byTaskType[type] ?? 0) + 1;
      if ((task['is_milestone'] as int? ?? 0) == 1) milestones++;
    }

    return {
      'total_count': tasks.length,
      'by_level': byLevel,
      'by_task_type': byTaskType,
      'milestones': milestones,
      'this_week': await _countOutputSince(db, weekStart),
      'this_month': await _countOutputSince(db, monthStart),
    };
  }

  Future<Map<String, dynamic>> getTimeDistribution({int days = 7}) async {
    final db = await LocalDb().database;
    final today = LocalTimeBoundary.dayStart(DateTime.now());
    final start = today.subtract(Duration(days: days - 1));
    final end = today.add(const Duration(days: 1));
    final events = await _focusEvents(db, start, end);
    final tags = await _observationTagMap(db);

    var totalMin = 0;
    final minutesByTag = <int, int>{};
    final countByTag = <int, int>{};
    final daily = <String, Map<String, dynamic>>{};

    for (final event in events) {
      totalMin += event.durationMin;
      final date = LocalTimeBoundary.dateKey(event.occurredAt);
      final day = daily.putIfAbsent(date, () => {
            'date': date,
            'total_min': 0,
            'work_count': 0,
          });
      day['total_min'] = (day['total_min'] as int) + event.durationMin;
      day['work_count'] = (day['work_count'] as int) + 1;
      final tagId = event.systemTagId;
      if (tagId != null) {
        minutesByTag[tagId] = (minutesByTag[tagId] ?? 0) + event.durationMin;
        countByTag[tagId] = (countByTag[tagId] ?? 0) + 1;
      }
    }

    final tagDist = <Map<String, dynamic>>[];
    for (final entry in minutesByTag.entries) {
      final tag = tags[entry.key];
      tagDist.add({
        'tag_id': entry.key,
        'name': tag?['name'] ?? '',
        'icon': tag?['icon'] ?? '',
        'total_min': entry.value,
        'session_count': countByTag[entry.key] ?? 0,
        'percent': totalMin == 0 ? 0.0 : entry.value / totalMin * 100,
      });
    }
    tagDist.sort((a, b) =>
        (b['total_min'] as int).compareTo(a['total_min'] as int));

    final byDay = <Map<String, dynamic>>[];
    for (var i = 0; i < days; i++) {
      final date = LocalTimeBoundary.dateKey(start.add(Duration(days: i)));
      byDay.add(daily[date] ?? {
        'date': date,
        'total_min': 0,
        'work_count': 0,
      });
    }
    return {'total_min': totalMin, 'tags': tagDist, 'by_day': byDay};
  }

  Future<Map<String, dynamic>> getWeeklyReview() async {
    final db = await LocalDb().database;
    final weekStart = LocalTimeBoundary.weekStart(DateTime.now());
    final weekEnd = weekStart.add(const Duration(days: 7));
    final lastWeekStart = weekStart.subtract(const Duration(days: 7));

    final focusThis = await _focusEvents(db, weekStart, weekEnd);
    final focusLast = await _focusEvents(db, lastWeekStart, weekStart);
    final output = await getOutputStats(period: 'week');
    final timeDist = await _timeDistributionForRange(db, focusThis);

    return {
      'week_start': LocalTimeBoundary.dateKey(weekStart),
      'week_end': LocalTimeBoundary.dateKey(
        weekEnd.subtract(const Duration(days: 1)),
      ),
      'habit_checked': await _countHabitLogsInRange(db, weekStart, weekEnd),
      'habit_last_week':
          await _countHabitLogsInRange(db, lastWeekStart, weekStart),
      'task_completed': await _countCompletedBetween(db, weekStart, weekEnd),
      'task_last_week':
          await _countCompletedBetween(db, lastWeekStart, weekStart),
      'focus_minutes':
          focusThis.fold<int>(0, (sum, event) => sum + event.durationMin),
      'focus_last_week':
          focusLast.fold<int>(0, (sum, event) => sum + event.durationMin),
      'output_count': output['total_count'] ?? 0,
      'output_by_level': output['by_level'] ?? <String, int>{},
      'milestones': output['milestones'] ?? 0,
      'time_distribution': timeDist,
    };
  }

  Future<List<Map<String, dynamic>>> getDailyTrend({int days = 7}) async {
    final db = await LocalDb().database;
    final today = LocalTimeBoundary.dayStart(DateTime.now());
    final habitTotal = await _countActiveHabits(db);
    final result = <Map<String, dynamic>>[];

    for (var i = days - 1; i >= 0; i--) {
      final start = today.subtract(Duration(days: i));
      final end = start.add(const Duration(days: 1));
      final created = await _countCreatedBetween(db, start, end);
      final cohortCompleted =
          await _countCreatedCohortCompleted(db, start, end);
      final actualCompleted = await _countCompletedBetween(db, start, end);
      final focus = await _focusEvents(db, start, end);
      final date = LocalTimeBoundary.dateKey(start);
      result.add({
        'date': date,
        'task_completed': actualCompleted,
        'task_total': created,
        'focus_minutes':
            focus.fold<int>(0, (sum, event) => sum + event.durationMin),
        'habit_checked': await _countHabitLogsByDate(db, date),
        'habit_total': habitTotal,
        'completion_rate':
            created == 0 ? 0 : cohortCompleted * 100 ~/ created,
      });
    }
    return result;
  }

  Future<Map<String, dynamic>> getDimensionSummary() async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now();
    final weekStart = LocalTimeBoundary.weekStart(now);
    final weekEnd = weekStart.add(const Duration(days: 7));
    final lastWeekStart = weekStart.subtract(const Duration(days: 7));
    final useEvents = await _tableExists(db, 'behavior_events');
    final result = <Map<String, dynamic>>[];

    for (final dimension in DimensionCatalog.all) {
      final tagIds = await _tagIdsForDimension(db, dimension.keyValue);
      final current = useEvents
          ? await _countBehaviorActivities(db, tagIds, weekStart, weekEnd)
          : await _countLegacyActivities(db, tagIds, weekStart, weekEnd);
      final previous = useEvents
          ? await _countBehaviorActivities(
              db, tagIds, lastWeekStart, weekStart)
          : await _countLegacyActivities(
              db, tagIds, lastWeekStart, weekStart);
      final lastAt = useEvents
          ? await _lastBehaviorActivity(db, tagIds)
          : await _lastLegacyActivity(db, tagIds);
      final trend = _trend(now, current, previous, lastAt);
      result.add({
        'key': dimension.keyValue,
        'name': dimension.name,
        'icon': dimension.icon,
        'color': dimension.color,
        'value': current,
        'total': 0,
        'unit': '次活动',
        'trend': trend.$1,
        'trend_desc': trend.$2,
        'last_record': lastAt?.toIso8601String() ?? '',
      });
    }
    return {'dimensions': result};
  }

  Future<int> _countOutputSince(Database db, DateTime start) async {
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM tasks WHERE deleted_at IS NULL "
      "AND is_completed = 1 AND output_level != '' AND completed_at >= ?",
      [start.toUtc().toIso8601String()],
    );
    return _count(rows);
  }

  Future<int> _countCompletedBetween(
    Database db,
    DateTime localStart,
    DateTime localEnd,
  ) async {
    final range = LocalTimeBoundary.range(localStart, localEnd);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM tasks WHERE deleted_at IS NULL '
      'AND is_completed = 1 AND completed_at >= ? AND completed_at < ?',
      [range.startUtc, range.endUtc],
    );
    return _count(rows);
  }

  Future<int> _countCreatedBetween(
    Database db,
    DateTime localStart,
    DateTime localEnd,
  ) async {
    final range = LocalTimeBoundary.range(localStart, localEnd);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM tasks WHERE deleted_at IS NULL '
      'AND created_at >= ? AND created_at < ?',
      [range.startUtc, range.endUtc],
    );
    return _count(rows);
  }

  Future<int> _countCreatedCohortCompleted(
    Database db,
    DateTime localStart,
    DateTime localEnd,
  ) async {
    final range = LocalTimeBoundary.range(localStart, localEnd);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM tasks WHERE deleted_at IS NULL '
      'AND created_at >= ? AND created_at < ? AND is_completed = 1',
      [range.startUtc, range.endUtc],
    );
    return _count(rows);
  }

  Future<int> _countActiveHabits(Database db) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM habits WHERE deleted_at IS NULL',
    );
    return _count(rows);
  }

  Future<int> _countHabitLogsByDate(Database db, String date) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM habit_logs hl '
      'INNER JOIN habits h ON h.id = hl.habit_id '
      'WHERE h.deleted_at IS NULL AND hl.date = ?',
      [date],
    );
    return _count(rows);
  }

  Future<int> _countHabitLogsInRange(
    Database db,
    DateTime localStart,
    DateTime localEnd,
  ) async {
    final start = LocalTimeBoundary.dateKey(localStart);
    final end = LocalTimeBoundary.dateKey(localEnd);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM habit_logs hl '
      'INNER JOIN habits h ON h.id = hl.habit_id '
      'WHERE h.deleted_at IS NULL AND hl.date >= ? AND hl.date < ?',
      [start, end],
    );
    return _count(rows);
  }

  Future<List<_FocusEvent>> _focusEvents(
    Database db,
    DateTime localStart,
    DateTime localEnd,
  ) async {
    final range = LocalTimeBoundary.range(localStart, localEnd);
    if (await _tableExists(db, 'behavior_events')) {
      final rows = await db.query(
        'behavior_events',
        where: "is_deleted = 0 AND event_type = 'session_ended' "
            'AND occurred_at >= ? AND occurred_at < ?',
        whereArgs: [range.startUtc, range.endUtc],
      );
      return rows
          .map((row) => _FocusEvent(
                occurredAt:
                    DateTime.parse(row['occurred_at'] as String).toLocal(),
                durationMin: row['duration_min'] as int? ?? 0,
                systemTagId: row['system_tag_id'] as int?,
              ))
          .toList();
    }
    if (!await _tableExists(db, 'work_sessions')) return const [];
    final rows = await db.query(
      'work_sessions',
      where: "session_type = 'work' AND ended_at IS NOT NULL "
          'AND ended_at >= ? AND ended_at < ?',
      whereArgs: [range.startUtc, range.endUtc],
    );
    return rows.map((row) {
      var minutes = (row['duration_sec'] as int? ?? 0) ~/ 60;
      if (minutes < 1) minutes = 1;
      return _FocusEvent(
        occurredAt: DateTime.parse(row['ended_at'] as String).toLocal(),
        durationMin: minutes,
        systemTagId: row['system_tag_id'] as int?,
      );
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _timeDistributionForRange(
    Database db,
    List<_FocusEvent> events,
  ) async {
    final tags = await _observationTagMap(db);
    final minutes = <int, int>{};
    final counts = <int, int>{};
    var total = 0;
    for (final event in events) {
      total += event.durationMin;
      final id = event.systemTagId;
      if (id == null) continue;
      minutes[id] = (minutes[id] ?? 0) + event.durationMin;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final result = <Map<String, dynamic>>[];
    for (final entry in minutes.entries) {
      result.add({
        'tag_id': entry.key,
        'name': tags[entry.key]?['name'] ?? '',
        'icon': tags[entry.key]?['icon'] ?? '',
        'total_min': entry.value,
        'session_count': counts[entry.key] ?? 0,
        'percent': total == 0 ? 0.0 : entry.value / total * 100,
      });
    }
    return result;
  }

  Future<Map<int, Map<String, Object?>>> _observationTagMap(Database db) async {
    final rows = await db.query('system_tags');
    return {
      for (final row in rows)
        if (row['id'] is int) row['id'] as int: row,
    };
  }

  Future<List<int>> _tagIdsForDimension(Database db, String key) async {
    final rows = await db.query(
      'system_tags',
      columns: ['id'],
      where: 'dimension_key = ?',
      whereArgs: [key],
    );
    return rows.map((row) => row['id'] as int).toList();
  }

  String _placeholders(int count) => List.filled(count, '?').join(',');

  Future<int> _countBehaviorActivities(
    Database db,
    List<int> tagIds,
    DateTime localStart,
    DateTime localEnd,
  ) async {
    if (tagIds.isEmpty) return 0;
    final range = LocalTimeBoundary.range(localStart, localEnd);
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM behavior_events "
      "WHERE is_deleted = 0 AND system_tag_id IN (${_placeholders(tagIds.length)}) "
      "AND event_type IN ('task_completed','habit_checked','session_ended') "
      'AND occurred_at >= ? AND occurred_at < ?',
      [...tagIds, range.startUtc, range.endUtc],
    );
    return _count(rows);
  }

  Future<DateTime?> _lastBehaviorActivity(
    Database db,
    List<int> tagIds,
  ) async {
    if (tagIds.isEmpty) return null;
    final rows = await db.rawQuery(
      "SELECT MAX(occurred_at) AS last_at FROM behavior_events "
      "WHERE is_deleted = 0 AND system_tag_id IN (${_placeholders(tagIds.length)}) "
      "AND event_type IN ('task_completed','habit_checked','session_ended')",
      tagIds,
    );
    return _parse(rows.firstOrNull?['last_at']);
  }

  Future<int> _countLegacyActivities(
    Database db,
    List<int> tagIds,
    DateTime localStart,
    DateTime localEnd,
  ) async {
    if (tagIds.isEmpty) return 0;
    final range = LocalTimeBoundary.range(localStart, localEnd);
    final placeholders = _placeholders(tagIds.length);
    final tasks = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM tasks WHERE deleted_at IS NULL '
      'AND system_tag_id IN ($placeholders) AND is_completed = 1 '
      'AND completed_at >= ? AND completed_at < ?',
      [...tagIds, range.startUtc, range.endUtc],
    );
    final habits = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM habit_logs hl '
      'INNER JOIN habits h ON h.id = hl.habit_id '
      'WHERE h.deleted_at IS NULL AND h.system_tag_id IN ($placeholders) '
      'AND hl.date >= ? AND hl.date < ?',
      [
        ...tagIds,
        LocalTimeBoundary.dateKey(localStart),
        LocalTimeBoundary.dateKey(localEnd),
      ],
    );
    var sessions = 0;
    if (await _tableExists(db, 'work_sessions')) {
      final rows = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM work_sessions WHERE session_type = 'work' "
        'AND system_tag_id IN ($placeholders) AND ended_at >= ? AND ended_at < ?',
        [...tagIds, range.startUtc, range.endUtc],
      );
      sessions = _count(rows);
    }
    return _count(tasks) + _count(habits) + sessions;
  }

  Future<DateTime?> _lastLegacyActivity(
    Database db,
    List<int> tagIds,
  ) async {
    if (tagIds.isEmpty) return null;
    final placeholders = _placeholders(tagIds.length);
    final tasks = await db.rawQuery(
      'SELECT MAX(completed_at) AS last_at FROM tasks '
      'WHERE deleted_at IS NULL AND system_tag_id IN ($placeholders) '
      'AND is_completed = 1',
      tagIds,
    );
    final habits = await db.rawQuery(
      'SELECT MAX(hl.created_at) AS last_at FROM habit_logs hl '
      'INNER JOIN habits h ON h.id = hl.habit_id '
      'WHERE h.deleted_at IS NULL AND h.system_tag_id IN ($placeholders)',
      tagIds,
    );
    final candidates = <DateTime?>[
      _parse(tasks.firstOrNull?['last_at']),
      _parse(habits.firstOrNull?['last_at']),
    ];
    if (await _tableExists(db, 'work_sessions')) {
      final sessions = await db.rawQuery(
        "SELECT MAX(ended_at) AS last_at FROM work_sessions "
        "WHERE session_type = 'work' AND system_tag_id IN ($placeholders) "
        'AND ended_at IS NOT NULL',
        tagIds,
      );
      candidates.add(_parse(sessions.firstOrNull?['last_at']));
    }
    DateTime? result;
    for (final value in candidates.whereType<DateTime>()) {
      if (result == null || value.isAfter(result)) result = value;
    }
    return result;
  }

  (String, String) _trend(
    DateTime now,
    int current,
    int previous,
    DateTime? lastAt,
  ) {
    if (lastAt == null) return ('quiet', '暂无记录');
    final days = now.difference(lastAt).inDays;
    if (days >= 3) return ('quiet', '$days天未记录');
    if (previous == 0) {
      return current > 0 ? ('up', '本周+$current') : ('flat', '本周0次');
    }
    final diff = current - previous;
    final ratio = diff / previous * 100;
    if (ratio > 20) return ('up', '+$diff 次');
    if (ratio < -20) return ('down', '$diff 次');
    return ('flat', '持平');
  }

  int _count(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return 0;
    return rows.first['cnt'] as int? ?? 0;
  }

  DateTime? _parse(Object? raw) => LocalTimeBoundary.parseInstant(raw);

  Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }
}

class _FocusEvent {
  final DateTime occurredAt;
  final int durationMin;
  final int? systemTagId;

  const _FocusEvent({
    required this.occurredAt,
    required this.durationMin,
    required this.systemTagId,
  });
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
