import '../db/local_db.dart';
import '../utils/local_time_boundary.dart';
import 'local_analytics_service.dart';
import 'local_dimension_analytics.dart';
import 'local_today_review_service.dart';

/// Local Review 兼容门面。
///
/// Today Review / Analytics 各自只有一个真实实现；本类只保留旧调用入口和
/// Tasks Review 的列表型聚合，避免再维护第二套 Facts/Dimension 规则。
class ReviewLocalService {
  static final ReviewLocalService _instance = ReviewLocalService._internal();
  factory ReviewLocalService() => _instance;
  ReviewLocalService._internal();

  Future<Map<String, dynamic>> computeTodayReview() =>
      LocalTodayReviewService().computeTodayReview();

  Future<Map<String, dynamic>> computeTasksReview(int days) async {
    final db = await LocalDb().database;
    final now = DateTime.now();
    final today = LocalTimeBoundary.dayStart(now);
    final end = today.add(const Duration(days: 1));
    final start = end.subtract(Duration(days: days));
    final range = LocalTimeBoundary.range(start, end);

    final tasks = await db.rawQuery(
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

    final createdRows = await db.rawQuery(
      '''SELECT COUNT(*) AS cnt FROM tasks
         WHERE deleted_at IS NULL AND created_at >= ? AND created_at < ?''',
      [range.startUtc, range.endUtc],
    );
    final createdCount = createdRows.first['cnt'] as int? ?? 0;

    final dailyCompleted = <String, int>{};
    final byType = <String, int>{};
    final byQuality = <String, int>{};
    var bestDayCount = 0;
    String? bestDay;

    for (final task in tasks) {
      final completedAt = LocalTimeBoundary.parseInstant(task['completed_at']);
      if (completedAt != null) {
        final date = LocalTimeBoundary.dateKey(completedAt);
        dailyCompleted[date] = (dailyCompleted[date] ?? 0) + 1;
        if (dailyCompleted[date]! > bestDayCount) {
          bestDayCount = dailyCompleted[date]!;
          bestDay = date;
        }
      }
      final type = task['task_type'] as String? ?? 'daily';
      byType[type] = (byType[type] ?? 0) + 1;
      final outputLevel = task['output_level'] as String? ?? '';
      if (outputLevel.isNotEmpty) {
        byQuality[outputLevel] = (byQuality[outputLevel] ?? 0) + 1;
      }
    }

    return {
      'summary': {
        'completed_count': tasks.length,
        'created_count': createdCount,
        'total_days': days,
        'best_day': bestDay != null
            ? {'date': bestDay, 'completed': bestDayCount}
            : null,
      },
      'completed_tasks': tasks.map(_taskToJson).toList(),
      'distribution': {
        'by_task_type': byType,
        'by_quality': byQuality,
      },
    };
  }

  Future<List<Map<String, dynamic>>> computeDailyTrend(int days) =>
      LocalAnalyticsService().getDailyTrend(days: days);

  Future<Map<String, dynamic>> computeOutputStats() =>
      LocalAnalyticsService().getOutputStats(period: 'all');

  Future<Map<String, dynamic>> computeDimensionSummary() =>
      LocalDimensionAnalytics().getSummary();

  Map<String, dynamic> _taskToJson(Map<String, dynamic> row) {
    final completedAt = LocalTimeBoundary.parseInstant(row['completed_at']);
    final formatted = completedAt == null
        ? ''
        : '${completedAt.hour.toString().padLeft(2, '0')}:${completedAt.minute.toString().padLeft(2, '0')}';
    return {
      'id': row['id'],
      'title': row['title'],
      'output_level': row['output_level'] as String? ?? '',
      'priority': row['priority'],
      'task_type': row['task_type'],
      'completed_at': formatted,
      'list_name': row['list_name'] as String? ?? '',
      'is_milestone': (row['is_milestone'] as int? ?? 0) == 1,
    };
  }
}
