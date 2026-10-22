import 'dart:math';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../db/local_db.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'local_migration_report_store.dart';
import '../repositories/migration_history_repository.dart';

class MigrationPlan {
  final Map<String, dynamic> snapshot;
  final Map<String, dynamic> preview;
  final String? authToken;

  const MigrationPlan({
    required this.snapshot,
    required this.preview,
    required this.authToken,
  });

  List<Map<String, dynamic>> get conflicts =>
      (preview['conflicts'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  Map<String, dynamic> get counts =>
      Map<String, dynamic>.from(preview['summary'] as Map);
}

class MigrationExecutionException implements Exception {
  final String message;
  final int localReportId;
  final bool outcomeUnknown;
  const MigrationExecutionException(
    this.message, this.localReportId, {required this.outcomeUnknown});
  @override
  String toString() => message;
}

/// 本地数据合并的客户端边界：先生成快照并请求只读预览，执行操作不在此阶段发生。
class MigrationService {
  Future<Map<String, dynamic>> preview() async {
    return (await prepare()).preview;
  }

  /// Snapshot and preview must be obtained together, not rebuilt on submit.
  Future<MigrationPlan> prepare() async {
    final snapshot = await _snapshot();
    final token = await AuthService.getToken();
    if (token == null || token.startsWith('local:')) {
      throw StateError('请先登录云端账号，再预览迁移');
    }
    final preview = await ApiService.previewMigration(snapshot);
    if (preview['preview_version'] is! String ||
        (preview['preview_version'] as String).isEmpty) {
      throw const FormatException('服务端迁移预览版本缺失，请升级服务端');
    }
    return MigrationPlan(
      snapshot: snapshot,
      preview: preview,
      authToken: token,
    );
  }

  /// Submit the exact preview snapshot and explicit choices.
  Future<Map<String, dynamic>> executePlan(
    MigrationPlan plan,
    Map<String, String> choices,
  ) async {
    if (plan.authToken != await AuthService.getToken()) {
      throw StateError('云端账号已变化，请重新预览迁移');
    }
    final current = await _snapshot();
    if (jsonEncode(current) != jsonEncode(plan.snapshot)) {
      throw StateError('本机数据已变化，请重新预览迁移');
    }
    if (choices.length != plan.conflicts.length) {
      throw StateError('仍有冲突尚未处理');
    }
    final normalized = <Map<String, dynamic>>[];
    for (final conflict in plan.conflicts) {
      final entity = conflict['entity']?.toString() ?? '';
      final id = (conflict['local_id'] as num?)?.toInt();
      final key = '$entity:$id';
      final policy = choices[key];
      if (id == null || !const ['cloud', 'local', 'both'].contains(policy)) {
        throw StateError('迁移冲突选择不完整，请重新确认');
      }
      normalized.add({
        'entity': entity,
        'local_id': id,
        'policy': policy,
      });
    }
    final payload = Map<String, dynamic>.from(plan.snapshot)
      ..['preview_version'] = plan.preview['preview_version']
      ..['conflict_choices'] = normalized
      ..['conflict_policy'] = 'reject';
    return _executeSnapshot(payload, 'reject');
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
      _verifyIdMap(snapshot, result['id_map']);
      await _applyIdMap(result['id_map']);
      await store.succeed(localID, result);
      return result;
    } catch (error) {
      await store.fail(localID, error);
      throw MigrationExecutionException(
        '迁移执行结果需要核对，请在迁移记录中检查回执并恢复映射。错误：$error',
        localID,
        outcomeUnknown: true,
      );
    }
  }

  /// A 200 response with a partial mapping must not be reported as a successful import.
  void _verifyIdMap(Map<String, dynamic> snapshot, Object? rawMap) {
    if (rawMap is! Map) {
      throw StateError('云端未返回可恢复的迁移 ID 映射');
    }
    for (final table in const [
      'lists', 'tags', 'system_tags', 'habits', 'tasks',
      'subtasks', 'habit_logs', 'sessions',
    ]) {
      final entries = snapshot[table] as List? ?? const [];
      final mapping = rawMap[table];
      if (entries.isNotEmpty && mapping is! Map) {
        throw StateError('云端缺少 $table 的迁移映射');
      }
      for (final item in entries) {
        if (item is! Map) continue;
        final id = item['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final value = mapping is Map ? mapping[id] : null;
        final remote = value is num ? value.toInt() : int.tryParse('$value');
        if (remote == null || remote <= 0) {
          throw StateError('云端未确认 $table 记录 $id 的迁移结果');
        }
      }
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
    final prefs = await SharedPreferences.getInstance();
    var sourceID = prefs.getString('slowlight_migration_source_id');
    if (sourceID == null || sourceID.isEmpty) {
      final secureRandom = Random.secure();
      sourceID = List.generate(
        16, (_) => secureRandom.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await prefs.setString('slowlight_migration_source_id', sourceID);
    }
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
      'source_id': sourceID,
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
