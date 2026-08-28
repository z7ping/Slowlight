import 'local_analytics_service.dart';
import '../db/local_db.dart';

/// StatsScreen 所需的基础统计，同样在 Local Data Mode 直接从 SQLite 计算。
extension LocalAnalyticsStats on LocalAnalyticsService {
  Future<Map<String, dynamic>> getTaskStats() async {
    final db = await LocalDb().database;
    final totalRows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM tasks WHERE deleted_at IS NULL',
    );
    final completedRows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM tasks WHERE deleted_at IS NULL AND is_completed = 1',
    );
    final total = totalRows.first['cnt'] as int? ?? 0;
    final completed = completedRows.first['cnt'] as int? ?? 0;

    final priorityRows = await db.rawQuery('''
      SELECT priority, COUNT(*) AS count
      FROM tasks
      WHERE deleted_at IS NULL AND is_completed = 0
      GROUP BY priority
    ''');
    final byListRows = await db.rawQuery('''
      SELECT l.id AS list_id, l.name AS list_name,
             COUNT(t.id) AS total,
             COALESCE(SUM(CASE WHEN t.is_completed = 1 THEN 1 ELSE 0 END), 0) AS completed
      FROM lists l
      LEFT JOIN tasks t ON t.list_id = l.id AND t.deleted_at IS NULL
      WHERE l.deleted_at IS NULL
      GROUP BY l.id, l.name
      ORDER BY l.sort_order
    ''');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daily = <Map<String, dynamic>>[];
    for (var i = 6; i >= 0; i--) {
      final start = today.subtract(Duration(days: i));
      final end = start.add(const Duration(days: 1));
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM tasks WHERE deleted_at IS NULL AND is_completed = 1 AND completed_at >= ? AND completed_at < ?',
        [start.toIso8601String(), end.toIso8601String()],
      );
      final count = rows.first['cnt'] as int? ?? 0;
      if (count > 0) {
        daily.add({'date': _localDate(start), 'count': count});
      }
    }

    return {
      'total': total,
      'completed': completed,
      'rate': total == 0 ? 0.0 : completed / total * 100,
      'priority': priorityRows.map((r) => {
            'priority': r['priority'] ?? 'none',
            'count': r['count'] ?? 0,
          }).toList(),
      'by_list': byListRows.map((r) => {
            'list_id': r['list_id'],
            'list_name': r['list_name'] ?? '',
            'total': r['total'] ?? 0,
            'completed': r['completed'] ?? 0,
          }).toList(),
      'daily': daily,
    };
  }

  Future<List<dynamic>> getListStats() async {
    final db = await LocalDb().database;
    final rows = await db.rawQuery('''
      SELECT l.id AS list_id, l.name AS list_name, l.color,
             COUNT(t.id) AS total,
             COALESCE(SUM(CASE WHEN t.is_completed = 1 THEN 1 ELSE 0 END), 0) AS completed
      FROM lists l
      LEFT JOIN tasks t ON t.list_id = l.id AND t.deleted_at IS NULL
      WHERE l.deleted_at IS NULL
      GROUP BY l.id, l.name, l.color, l.sort_order
      ORDER BY l.sort_order
    ''');
    return rows.map((row) {
      final total = row['total'] as int? ?? 0;
      final completed = row['completed'] as int? ?? 0;
      return {
        'list_id': row['list_id'],
        'list_name': row['list_name'] ?? '',
        'color': row['color'] ?? '#1890ff',
        'total': total,
        'completed': completed,
        'rate': total == 0 ? 0.0 : completed / total * 100,
      };
    }).toList();
  }

  Future<List<dynamic>> getTagStats() async {
    final db = await LocalDb().database;
    final rows = await db.rawQuery('''
      SELECT t.id AS tag_id, t.name, t.color, COUNT(task.id) AS task_num
      FROM tags t
      LEFT JOIN task_tags tt ON tt.tag_id = t.id
      LEFT JOIN tasks task ON task.id = tt.task_id AND task.deleted_at IS NULL
      GROUP BY t.id, t.name, t.color
      ORDER BY task_num DESC
    ''');
    return rows.map((row) => {
          'tag_id': row['tag_id'],
          'name': row['name'] ?? '',
          'color': row['color'] ?? '#0075de',
          'task_num': row['task_num'] ?? 0,
        }).toList();
  }
}

String _localDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
