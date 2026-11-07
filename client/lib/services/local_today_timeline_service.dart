import '../db/local_behavior_event_schema.dart';
import '../db/local_db.dart';
import '../db/local_product_core_schema.dart';
import '../models/today_timeline_item.dart';
import '../utils/local_time_boundary.dart';

/// Local Data 直接读取行为事实和第一方观察；不读取全量任务后推测事件。
class LocalTodayTimelineService {
  Future<List<TodayTimelineItem>> getTodayTimeline() async =>
      (await getPeriodTimeline()).items;

  Future<ReviewPeriodTimeline> getPeriodTimeline({
    String period = 'today',
    int offset = 0,
    int limit = 40,
  }) async {
    if (period != 'today' && period != 'week' && period != 'month') {
      throw ArgumentError.value(period, 'period', 'Unsupported review period');
    }
    if (offset < 0 || offset > 1000000 || limit < 1 || limit > 40) {
      throw RangeError('Invalid review timeline page');
    }
    final sourceLimit = offset + limit + 1;
    await LocalProductCoreSchema.ensureReady();
    await LocalBehaviorEventSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now();
    final start = switch (period) {
      'week' => LocalTimeBoundary.weekStart(now),
      'month' => LocalTimeBoundary.addCalendarDays(
          LocalTimeBoundary.dayStart(now), -29),
      _ => LocalTimeBoundary.dayStart(now),
    };
    final range = LocalTimeBoundary.range(
      start, LocalTimeBoundary.dayEnd(now),
    );
    final todayDate = LocalTimeBoundary.dateKey(now);
    // The original today-only metadata guard is retained for today's path.
    final habitDateFilter = period == 'today' ? 'AND be.metadata = ?' : '';
    final eventArgs = <Object?>[
      range.startUtc,
      range.endUtc,
      if (period == 'today') '{"date":"$todayDate"}',
    ];

    final events = await db.rawQuery('''
      SELECT 'event:' || be.id AS id,
        be.event_type AS kind,
        COALESCE(t.title, h.name, '') AS title,
        be.duration_min AS duration_min,
        be.occurred_at AS occurred_at
      FROM behavior_events be
      LEFT JOIN tasks t
        ON be.entity_type = 'task' AND t.id = be.entity_id
        AND t.deleted_at IS NULL AND t.is_completed = 1
      LEFT JOIN habits h
        ON be.entity_type = 'habit' AND h.id = be.entity_id
        AND h.deleted_at IS NULL
      WHERE be.is_deleted = 0
        AND be.occurred_at >= ? AND be.occurred_at < ?
        AND (
          (be.event_type = 'task_completed' AND t.id IS NOT NULL)
          OR (be.event_type = 'habit_checked' AND h.id IS NOT NULL
              $habitDateFilter)
          OR be.event_type = 'session_ended'
        )
      ORDER BY be.occurred_at DESC, be.id DESC
      LIMIT ?
    ''', [...eventArgs, sourceLimit]);

    final reflections = await db.rawQuery('''
      SELECT 'reflection:' || id AS id, entry_type AS kind,
        content AS title, 0 AS duration_min, created_at AS occurred_at
      FROM reflections
      WHERE deleted_at IS NULL
        AND entry_type IN ('observation', 'reflection')
        AND created_at >= ? AND created_at < ?
      ORDER BY created_at DESC, id DESC
      LIMIT ?
    ''', [range.startUtc, range.endUtc, sourceLimit]);

    final totals = await db.rawQuery('''
      SELECT COUNT(*) AS observation_count
      FROM reflections
      WHERE deleted_at IS NULL AND entry_type = 'observation'
        AND created_at >= ? AND created_at < ?
    ''', [range.startUtc, range.endUtc]);
    final count = totals.first['observation_count'];
    if (count is! int) {
      throw StateError('Invalid observation count');
    }
    final items = TodayTimelineItem.sorted([...events, ...reflections]
        .map((row) => TodayTimelineItem.fromJson(Map<String, dynamic>.from(row)))
        .whereType<TodayTimelineItem>());
    return ReviewPeriodTimeline(
      items: items.skip(offset).take(limit).toList(growable: false),
      observationCount: count,
      hasMore: items.length > offset + limit,
    );
  }
}
