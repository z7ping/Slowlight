import '../db/local_behavior_event_schema.dart';
import '../db/local_db.dart';
import '../db/local_product_core_schema.dart';
import '../models/today_timeline_item.dart';
import '../utils/local_time_boundary.dart';

/// Local Data 直接读取行为事实和第一方观察；不读取全量任务后推测事件。
class LocalTodayTimelineService {
  Future<List<TodayTimelineItem>> getTodayTimeline() async {
    await LocalProductCoreSchema.ensureReady();
    await LocalBehaviorEventSchema.ensureReady();
    final db = await LocalDb().database;
    final range = LocalTimeBoundary.dayRange(DateTime.now());

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
          OR (be.event_type = 'habit_checked' AND h.id IS NOT NULL)
          OR be.event_type = 'session_ended'
        )
      ORDER BY be.occurred_at DESC, be.id DESC
      LIMIT 60
    ''', [range.startUtc, range.endUtc]);

    final reflections = await db.rawQuery('''
      SELECT 'reflection:' || id AS id, entry_type AS kind,
        content AS title, 0 AS duration_min, created_at AS occurred_at
      FROM reflections
      WHERE deleted_at IS NULL
        AND entry_type IN ('observation', 'reflection')
        AND created_at >= ? AND created_at < ?
      ORDER BY created_at DESC, id DESC
      LIMIT 60
    ''', [range.startUtc, range.endUtc]);

    final items = [...events, ...reflections]
        .map((row) => TodayTimelineItem.fromJson(Map<String, dynamic>.from(row)))
        .whereType<TodayTimelineItem>();
    return TodayTimelineItem.sorted(items).take(40).toList(growable: false);
  }
}
