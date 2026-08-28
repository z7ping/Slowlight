import 'package:sqflite/sqflite.dart';

import '../db/local_db.dart';
import '../db/local_product_core_schema.dart';
import '../models/dimension.dart';

/// 四维度统计只认稳定 DimensionKey，不再把任意 SystemTag 当作人生维度。
class LocalDimensionAnalytics {
  Future<Map<String, dynamic>> getSummary() async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final lastWeekStart = weekStart.subtract(const Duration(days: 7));

    final result = <Map<String, dynamic>>[];
    for (final dimension in DimensionCatalog.all) {
      final current = await _count(
        db,
        dimension.keyValue,
        weekStart,
        weekEnd,
      );
      final previous = await _count(
        db,
        dimension.keyValue,
        lastWeekStart,
        weekStart,
      );
      final last = await _lastActivity(db, dimension.keyValue);
      final trend = _trend(now, current, previous, last);
      final activeDays = await _activeDays(db, dimension.keyValue, today);
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
        'last_record': last?.toIso8601String() ?? '',
        'active_days': activeDays,
      });
    }
    return {'dimensions': result};
  }

  Future<int> _count(
    Database db,
    String dimensionKey,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS cnt
      FROM behavior_events be
      INNER JOIN system_tags st ON st.id = be.system_tag_id
      WHERE be.is_deleted = 0
        AND st.dimension_key = ?
        AND be.event_type IN ('task_completed', 'habit_checked', 'session_ended')
        AND be.occurred_at >= ?
        AND be.occurred_at < ?
      ''',
      [
        dimensionKey,
        start.toUtc().toIso8601String(),
        end.toUtc().toIso8601String(),
      ],
    );
    return rows.isEmpty ? 0 : (rows.first['cnt'] as int? ?? 0);
  }

  Future<List<String>> _activeDays(
    Database db,
    String dimensionKey,
    DateTime today,
  ) async {
    final result = <String>[];
    for (var offset = 6; offset >= 0; offset--) {
      final start = today.subtract(Duration(days: offset));
      final end = start.add(const Duration(days: 1));
      if (await _count(db, dimensionKey, start, end) > 0) {
        result.add(_dateKey(start));
      }
    }
    return result;
  }

  Future<DateTime?> _lastActivity(Database db, String dimensionKey) async {
    final rows = await db.rawQuery(
      '''
      SELECT MAX(be.occurred_at) AS last_at
      FROM behavior_events be
      INNER JOIN system_tags st ON st.id = be.system_tag_id
      WHERE be.is_deleted = 0
        AND st.dimension_key = ?
        AND be.event_type IN ('task_completed', 'habit_checked', 'session_ended')
      ''',
      [dimensionKey],
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['last_at'] as String?;
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  (String, String) _trend(
    DateTime now,
    int current,
    int previous,
    DateTime? last,
  ) {
    if (last == null) return ('quiet', '暂无记录');
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(last.year, last.month, last.day))
        .inDays;
    if (days >= 3) return ('quiet', '$days天未记录');
    if (previous == 0) {
      return current > 0 ? ('up', '本周+$current') : ('flat', '本周0次');
    }
    final diff = current - previous;
    final ratio = diff / previous;
    if (ratio > .2) return ('up', '+$diff 次');
    if (ratio < -.2) return ('down', '$diff 次');
    return ('flat', '持平');
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
