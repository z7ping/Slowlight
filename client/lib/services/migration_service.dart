import '../db/local_db.dart';
import 'api_service.dart';
import 'local_migration_report_store.dart';
import '../repositories/migration_history_repository.dart';

/// 本地数据合并的客户端边界：先生成快照并请求只读预览，执行操作不在此阶段发生。
class MigrationService {
  Future<Map<String, dynamic>> preview() async {
    return ApiService.previewMigration(await _snapshot());
  }

  Future<Map<String, dynamic>?> latestReport() =>
      MigrationHistoryRepository().latest();

  Future<List<Map<String, dynamic>>> reports() =>
      MigrationHistoryRepository().all();

  Future<Map<String, dynamic>> execute(
      {String conflictPolicy = 'reject'}) async {
    final snapshot = await _snapshot();
    return _executeSnapshot(snapshot, conflictPolicy);
  }

  /// 只重放本机留痕中的失败快照；成功或云端审计记录不具备重试资格。
  Future<Map<String, dynamic>> retryLocalReport(int reportID) async {
    final store = LocalMigrationReportStore();
    final snapshot = await store.retrySnapshot(reportID);
    if (snapshot == null) throw StateError('该记录不可重试');
    return _executeSnapshot(
        snapshot, snapshot['conflict_policy']?.toString() ?? 'reject');
  }

  Future<Map<String, dynamic>> _executeSnapshot(
      Map<String, dynamic> snapshot, String conflictPolicy) async {
    snapshot['conflict_policy'] = conflictPolicy;
    final store = LocalMigrationReportStore();
    final localID = await store.start(snapshot, conflictPolicy);
    try {
      final result = await ApiService.executeMigration(snapshot);
      await _applyIdMap(result['id_map']);
      await store.succeed(localID, result);
      return result;
    } catch (error) {
      await store.fail(localID, error);
      rethrow;
    }
  }

  Future<void> _applyIdMap(Object? rawMap) async {
    if (rawMap is! Map) return;
    const tables = {
      'lists': 'lists',
      'tags': 'tags',
      'system_tags': 'system_tags',
      'habits': 'habits',
      'tasks': 'tasks',
      'subtasks': 'subtasks',
      'habit_logs': 'habit_logs',
    };
    final db = await LocalDb().database;
    await db.transaction((txn) async {
      for (final entry in tables.entries) {
        final rawEntries = rawMap[entry.key];
        if (rawEntries is! Map) continue;
        for (final mapping in rawEntries.entries) {
          final localID = int.tryParse(mapping.key.toString());
          final serverID = mapping.value is num
              ? (mapping.value as num).toInt()
              : int.tryParse(mapping.value.toString());
          if (localID == null || serverID == null) continue;
          await txn.update(entry.value, {'server_id': serverID},
              where: 'id = ?', whereArgs: [localID]);
        }
      }
    });
  }

  Future<Map<String, dynamic>> _snapshot() async {
    final db = await LocalDb().database;
    final lists = await db.query('lists', where: 'deleted_at IS NULL');
    final tags = await db.query('tags');
    final systemTags = await db.query('system_tags');
    final habits = await db.query('habits', where: 'deleted_at IS NULL');
    final tasks = await db.query('tasks', where: 'deleted_at IS NULL');
    final subtasks = await db.query('subtasks');
    final taskTags = await db.query('task_tags');
    final habitLogs = await db.query('habit_logs');
    final sessions = await db.query('work_sessions');

    return {
      'lists': lists.map(_list).toList(),
      'tags': tags.map(_tag).toList(),
      'system_tags': systemTags.map(_tag).toList(),
      'habits': habits.map(_habit).toList(),
      'tasks': tasks
          .map((row) => _task(
              row,
              taskTags
                  .where((link) => link['task_id'] == row['id'])
                  .map((link) => link['tag_id'])
                  .whereType<int>()
                  .toList()))
          .toList(),
      'subtasks': subtasks.map(_subtask).toList(),
      'habit_logs': habitLogs.map(_log).toList(),
      'sessions': sessions.map(_session).toList(),
    };
  }

  Map<String, dynamic> _list(Map<String, Object?> row) => {
        'id': row['id'],
        'name': row['name'],
        'icon': row['icon'],
        'color': row['color'],
        'is_inbox': row['is_inbox'] == 1,
      };

  Map<String, dynamic> _tag(Map<String, Object?> row) => {
        'id': row['id'],
        'name': row['name'],
        'icon': row['icon'],
        'color': row['color'],
      };

  Map<String, dynamic> _habit(Map<String, Object?> row) => {
        'id': row['id'],
        'name': row['name'],
        'icon': row['icon'],
        'color': row['color'],
        'frequency': row['frequency'],
        'target_days': row['target_days'],
        'preferred_period': row['preferred_period'],
        'duration_min': row['duration_min'],
        'generate_task': row['generate_task'] == 1,
        'show_checkin_dialog': row['show_checkin_dialog'] == 1,
        'specific_time': row['specific_time'],
        'reminder_at': row['reminder_at'],
        'system_tag_id': row['system_tag_id'],
      };

  Map<String, dynamic> _task(Map<String, Object?> row, List<int> tagIds) => {
        'id': row['id'],
        'list_id': row['list_id'],
        'title': row['title'],
        'description': row['description'],
        'priority': row['priority'],
        'is_completed': row['is_completed'] == 1,
        'sort_order': row['sort_order'],
        'repeat_type': row['repeat_type'],
        'repeat_interval': row['repeat_interval'],
        'repeat_days': row['repeat_days'],
        'task_type': row['task_type'],
        'mood_before': row['mood_before'],
        'mood_after': row['mood_after'],
        'is_milestone': row['is_milestone'] == 1,
        'obsidian_link': row['obsidian_link'],
        'output_level': row['output_level'],
        'due_date': row['due_date'],
        'due_time': row['due_time'],
        'completed_at': row['completed_at'],
        'reminder_at': row['reminder_at'],
        'reminder_advance_minutes': row['reminder_advance_minutes'],
        'system_tag_id': row['system_tag_id'],
        'tag_ids': tagIds,
      };

  Map<String, dynamic> _log(Map<String, Object?> row) => {
        'id': row['id'],
        'habit_id': row['habit_id'],
        'task_id': row['task_id'],
        'date': row['date'],
        'period': row['period'],
        'duration_min': row['duration_min'],
        'note': row['note'],
      };

  Map<String, dynamic> _subtask(Map<String, Object?> row) => {
        'id': row['id'],
        'task_id': row['task_id'],
        'title': row['title'],
        'is_completed': row['is_completed'] == 1,
        'sort_order': row['sort_order']
      };

  Map<String, dynamic> _session(Map<String, Object?> row) => {
        'id': row['id'],
        'session_type': row['session_type'] ?? row['type'] ?? 'work',
        'task_id': row['task_id'],
        'system_tag_id': row['system_tag_id'],
        'started_at': row['started_at'],
        'ended_at': row['ended_at'],
        'duration_sec': row['duration_sec'],
        'device': row['device'],
      };
}
