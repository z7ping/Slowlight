import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/cloud_cache_db.dart';
import '../models/tag.dart';
import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';

/// Cloud Data Mode 的离线缓存访问层。
///
/// SQLite 内部始终使用本地自增 ID / 本地外键；对 Cloud UI 暴露：
/// - 已同步实体：server_id；
/// - 离线新建实体：负数临时 ID（-local_id）。
///
/// 这样不会把 Cloud cache 的内部 ID 泄漏成服务端 ID，也不需要修改领域 DTO。
class CloudCacheRepository {
  final CloudCacheDb _cache = CloudCacheDb();

  Future<Database> get _db => _cache.database;

  Future<List<TodoList>> getLists() async {
    final db = await _db;
    final rows = await db.query(
      'lists',
      where: 'deleted_at IS NULL',
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return [for (final row in rows) _listFromRow(row)];
  }

  Future<TodoList> createList({
    required String name,
    String icon = '📁',
    String color = '#1890ff',
    bool isInbox = false,
  }) async {
    final db = await _db;
    final now = _now();
    final localId = await db.insert('lists', {
      'name': name,
      'icon': icon,
      'color': color,
      'is_inbox': isInbox ? 1 : 0,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
      'last_modified': now,
    });
    await SyncService().enqueue(
      entityType: 'lists',
      entityLocalId: localId,
      operation: 'create',
    );
    return _listFromRow(
      (await db.query('lists', where: 'id = ?', whereArgs: [localId])).single,
    );
  }

  Future<TodoList> updateList({
    required int publicId,
    String? name,
    String? icon,
    String? color,
  }) async {
    final db = await _db;
    final row = await _rowByPublicId(db, 'lists', publicId);
    final localId = row['id'] as int;
    final serverId = row['server_id'] as int?;
    final now = _now();
    await db.update(
      'lists',
      {
        if (name != null) 'name': name,
        if (icon != null) 'icon': icon,
        if (color != null) 'color': color,
        'updated_at': now,
        'last_modified': now,
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
    // 尚未创建到服务端时，原 create queue 会在 push 时读取最新 row。
    if (serverId != null) {
      await SyncService().enqueue(
        entityType: 'lists',
        entityLocalId: localId,
        entityServerId: serverId,
        operation: 'update',
      );
    }
    return _listFromRow(
      (await db.query('lists', where: 'id = ?', whereArgs: [localId])).single,
    );
  }

  Future<void> deleteList(int publicId) async {
    final db = await _db;
    final row = await _rowByPublicId(db, 'lists', publicId);
    final localId = row['id'] as int;
    await db.update(
      'lists',
      {'deleted_at': _now()},
      where: 'id = ?',
      whereArgs: [localId],
    );
    await SyncService().enqueue(
      entityType: 'lists',
      entityLocalId: localId,
      entityServerId: row['server_id'] as int?,
      operation: 'delete',
    );
  }

  Future<List<Task>> getAllTasks() async {
    final db = await _db;
    final rows = await db.query(
      'tasks',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
    return Future.wait(rows.map((row) => _taskFromRow(db, row)));
  }

  Future<List<Task>> getTasks(int listPublicId) async {
    final db = await _db;
    final listLocalId = await _localId(db, 'lists', listPublicId);
    final rows = await db.query(
      'tasks',
      where: 'list_id = ? AND deleted_at IS NULL',
      whereArgs: [listLocalId],
      orderBy: 'created_at DESC',
    );
    return Future.wait(rows.map((row) => _taskFromRow(db, row)));
  }

  Future<List<Task>> getTodayTasks() async {
    final db = await _db;
    final date = _dateKey(DateTime.now())!;
    final rows = await db.query(
      'tasks',
      where:
          'deleted_at IS NULL AND (due_date = ? OR due_date IS NULL OR (due_date < ? AND is_completed = 0))',
      whereArgs: [date, date],
      orderBy: "CASE WHEN due_date IS NULL THEN 1 "
          "WHEN due_date = '$date' AND is_completed = 1 THEN 0 "
          "WHEN due_date = '$date' AND is_completed = 0 THEN 1 "
          'ELSE 2 END, created_at DESC',
    );
    return Future.wait(rows.map((row) => _taskFromRow(db, row)));
  }

  Future<List<Task>> getCompletedTasks() async {
    final all = await getAllTasks();
    return all.where((task) => task.isCompleted).toList(growable: false);
  }

  Future<List<Task>> searchTasks(String query) async {
    final text = query.trim().toLowerCase();
    if (text.isEmpty) return const [];
    final all = await getAllTasks();
    return all
        .where((task) =>
            task.title.toLowerCase().contains(text) ||
            (task.description ?? '').toLowerCase().contains(text))
        .toList(growable: false);
  }

  Future<List<Task>> getTasksForMonth(int year, int month) async {
    final all = await getAllTasks();
    return all.where((task) {
      final due = task.dueDate;
      return due != null && due.year == year && due.month == month;
    }).toList(growable: false);
  }

  Future<Task> createTask({
    required int listId,
    required String title,
    String? description,
    String priority = 'none',
    DateTime? dueDate,
    String? dueTime,
    String repeatType = 'none',
    int repeatInterval = 1,
    String repeatDays = '',
    DateTime? reminderAt,
    int reminderAdvanceMinutes = 0,
    List<int>? tagIds,
    int? systemTagId,
    String taskType = 'daily',
    int moodBefore = 0,
    int moodAfter = 0,
    bool isMilestone = false,
    int? relatedQuestId,
    String obsidianLink = '',
    String outputLevel = '',
  }) async {
    final db = await _db;
    final listLocalId = await _localId(db, 'lists', listId);
    final systemTagLocalId = systemTagId == null
        ? null
        : await _localId(db, 'system_tags', systemTagId);
    final relatedLocalId = relatedQuestId == null
        ? null
        : await _localId(db, 'tasks', relatedQuestId);
    final now = _now();
    final localId = await db.insert('tasks', {
      'list_id': listLocalId,
      'title': title,
      'description': description ?? '',
      'priority': priority,
      'due_date': _dateKey(dueDate),
      'due_time': dueTime,
      'repeat_type': repeatType,
      'repeat_interval': repeatInterval,
      'repeat_days': repeatDays,
      'reminder_at': reminderAt?.toUtc().toIso8601String(),
      'reminder_advance_minutes': reminderAdvanceMinutes,
      'system_tag_id': systemTagLocalId,
      'task_type': taskType,
      'mood_before': moodBefore,
      'mood_after': moodAfter,
      'is_milestone': isMilestone ? 1 : 0,
      'related_quest_id': relatedLocalId,
      'obsidian_link': obsidianLink,
      'output_level': outputLevel,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
      'last_modified': now,
    });
    await _replaceTaskTags(db, localId, tagIds ?? const []);
    await SyncService().enqueue(
      entityType: 'tasks',
      entityLocalId: localId,
      operation: 'create',
    );
    return _taskByLocalId(db, localId);
  }

  Future<Task> updateTask({
    required int taskId,
    required int listId,
    required String title,
    String? description,
    String priority = 'none',
    DateTime? dueDate,
    String? dueTime,
    String repeatType = 'none',
    int repeatInterval = 1,
    String repeatDays = '',
    DateTime? reminderAt,
    int reminderAdvanceMinutes = 0,
    List<int>? tagIds,
    int? systemTagId,
    String taskType = 'daily',
    int moodBefore = 0,
    int moodAfter = 0,
    bool isMilestone = false,
    int? relatedQuestId,
    String obsidianLink = '',
    String outputLevel = '',
  }) async {
    final db = await _db;
    final row = await _rowByPublicId(db, 'tasks', taskId);
    final localId = row['id'] as int;
    final serverId = row['server_id'] as int?;
    final listLocalId = await _localId(db, 'lists', listId);
    final systemTagLocalId = systemTagId == null
        ? null
        : await _localId(db, 'system_tags', systemTagId);
    final relatedLocalId = relatedQuestId == null
        ? null
        : await _localId(db, 'tasks', relatedQuestId);
    final now = _now();
    await db.update(
      'tasks',
      {
        'list_id': listLocalId,
        'title': title,
        'description': description ?? '',
        'priority': priority,
        'due_date': _dateKey(dueDate),
        'due_time': dueTime,
        'repeat_type': repeatType,
        'repeat_interval': repeatInterval,
        'repeat_days': repeatDays,
        'reminder_at': reminderAt?.toUtc().toIso8601String(),
        'reminder_advance_minutes': reminderAdvanceMinutes,
        'system_tag_id': systemTagLocalId,
        'task_type': taskType,
        'mood_before': moodBefore,
        'mood_after': moodAfter,
        'is_milestone': isMilestone ? 1 : 0,
        'related_quest_id': relatedLocalId,
        'obsidian_link': obsidianLink,
        'output_level': outputLevel,
        'updated_at': now,
        'last_modified': now,
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
    if (tagIds != null) await _replaceTaskTags(db, localId, tagIds);
    if (serverId != null) {
      await SyncService().enqueue(
        entityType: 'tasks',
        entityLocalId: localId,
        entityServerId: serverId,
        operation: 'update',
      );
    }
    return _taskByLocalId(db, localId);
  }

  Future<void> deleteTask(int publicId) async {
    final db = await _db;
    final row = await _rowByPublicId(db, 'tasks', publicId);
    final localId = row['id'] as int;
    await db.update(
      'tasks',
      {'deleted_at': _now()},
      where: 'id = ?',
      whereArgs: [localId],
    );
    await SyncService().enqueue(
      entityType: 'tasks',
      entityLocalId: localId,
      entityServerId: row['server_id'] as int?,
      operation: 'delete',
    );
  }

  Future<List<Map<String, dynamic>>> getHabits() async {
    final db = await _db;
    final rows = await db.query(
      'habits',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at ASC',
    );
    final user = await AuthService.getUser();
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final publicId = _publicId(row);
      final localId = row['id'] as int;
      final logs = await db.query(
        'habit_logs',
        where: 'habit_id = ?',
        whereArgs: [localId],
      );
      final days = logs.map((value) => value['date']?.toString() ?? '').toList();
      final today = _dateKey(DateTime.now());
      result.add({
        'id': publicId,
        'user_id': user?.id ?? 0,
        'name': row['name'] ?? '',
        'icon': row['icon'] ?? '✅',
        'color': row['color'] ?? '#52c41a',
        'frequency': row['frequency'] ?? 'daily',
        'target_days': row['target_days'] ?? 0,
        'streak_count': row['streak_count'] ?? 0,
        'preferred_period': row['preferred_period'] ?? '',
        'system_tag_id': await _publicForeignId(
          db,
          'system_tags',
          row['system_tag_id'] as int?,
        ),
        'generate_task': (row['generate_task'] as int? ?? 0) == 1,
        'show_checkin_dialog':
            (row['show_checkin_dialog'] as int? ?? 0) == 1,
        'duration_min': row['duration_min'] ?? 0,
        'specific_time': row['specific_time'] ?? '',
        'reminder_at': _jsonMap(row['reminder_at']),
        'checked_today': days.contains(today),
        'checked_days': days,
        'created_at': row['created_at'],
      });
    }
    return result;
  }

  Future<Map<String, dynamic>> createHabit({
    required String name,
    String icon = '✅',
    String color = '#52c41a',
    String frequency = 'daily',
    int targetDays = 0,
    int? systemTagId,
    String preferredPeriod = '',
    int durationMin = 0,
    bool generateTask = false,
    bool showCheckinDialog = false,
    String specificTime = '',
    Map<String, dynamic>? reminderAt,
  }) async {
    final db = await _db;
    final systemTagLocalId = systemTagId == null
        ? null
        : await _localId(db, 'system_tags', systemTagId);
    final now = _now();
    final localId = await db.insert('habits', {
      'name': name,
      'icon': icon,
      'color': color,
      'frequency': frequency,
      'target_days': targetDays,
      'system_tag_id': systemTagLocalId,
      'preferred_period': preferredPeriod,
      'duration_min': durationMin,
      'generate_task': generateTask ? 1 : 0,
      'show_checkin_dialog': showCheckinDialog ? 1 : 0,
      'specific_time': specificTime,
      'reminder_at': jsonEncode(reminderAt ?? const {}),
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
      'last_modified': now,
    });
    await SyncService().enqueue(
      entityType: 'habits',
      entityLocalId: localId,
      operation: 'create',
    );
    return _habitByPublicId(-localId);
  }

  Future<void> updateHabit(int publicId, Map<String, dynamic> data) async {
    final db = await _db;
    final row = await _rowByPublicId(db, 'habits', publicId);
    final localId = row['id'] as int;
    final serverId = row['server_id'] as int?;
    final updates = Map<String, dynamic>.from(data);
    if (updates.containsKey('system_tag_id')) {
      final publicTagId = updates['system_tag_id'] as int?;
      updates['system_tag_id'] = publicTagId == null
          ? null
          : await _localId(db, 'system_tags', publicTagId);
    }
    if (updates.containsKey('reminder_at')) {
      updates['reminder_at'] = jsonEncode(updates['reminder_at'] ?? const {});
    }
    updates['updated_at'] = _now();
    updates['last_modified'] = _now();
    await db.update('habits', updates, where: 'id = ?', whereArgs: [localId]);
    if (serverId != null) {
      await SyncService().enqueue(
        entityType: 'habits',
        entityLocalId: localId,
        entityServerId: serverId,
        operation: 'update',
      );
    }
  }

  Future<Map<String, dynamic>> checkInHabit(
    int publicId, {
    String note = '',
    String? date,
    int? durationMin,
    String? period,
  }) async {
    final db = await _db;
    final habitRow = await _rowByPublicId(db, 'habits', publicId);
    final habitLocalId = habitRow['id'] as int;
    final day = date ?? _dateKey(DateTime.now())!;
    final existing = await db.query(
      'habit_logs',
      where: 'habit_id = ? AND date = ?',
      whereArgs: [habitLocalId, day],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return {'log': await _habitLogMap(db, existing.first)};
    }
    final now = _now();
    final logLocalId = await db.insert('habit_logs', {
      'habit_id': habitLocalId,
      'date': day,
      'period': period ?? '',
      'duration_min': durationMin ?? 0,
      'note': note,
      'created_at': now,
      'sync_status': 'pending',
      'last_modified': now,
    });
    await SyncService().enqueue(
      entityType: 'habit_logs',
      entityLocalId: logLocalId,
      operation: 'create',
    );
    final log = (await db.query(
      'habit_logs',
      where: 'id = ?',
      whereArgs: [logLocalId],
    )).single;
    return {'log': await _habitLogMap(db, log), 'checked': true};
  }

  Future<Map<String, dynamic>> getHabitLogs(int publicId, {String? month}) async {
    final db = await _db;
    final habitLocalId = await _localId(db, 'habits', publicId);
    final rows = await db.query(
      'habit_logs',
      where: month == null ? 'habit_id = ?' : 'habit_id = ? AND date LIKE ?',
      whereArgs: month == null ? [habitLocalId] : [habitLocalId, '$month%'],
      orderBy: 'date DESC',
    );
    final logs = <Map<String, dynamic>>[];
    for (final row in rows) {
      logs.add(await _habitLogMap(db, row));
    }
    return {'logs': logs};
  }

  Future<void> deleteHabit(int publicId) async {
    final db = await _db;
    final row = await _rowByPublicId(db, 'habits', publicId);
    final localId = row['id'] as int;
    await db.update('habits', {'deleted_at': _now()},
        where: 'id = ?', whereArgs: [localId]);
    await SyncService().enqueue(
      entityType: 'habits',
      entityLocalId: localId,
      entityServerId: row['server_id'] as int?,
      operation: 'delete',
    );
  }

  /// 当前服务端“取消打卡”按习惯 + 当天语义执行；离线缓存保持相同语义。
  Future<Map<String, dynamic>> uncheckInHabit(int publicId) async {
    final db = await _db;
    final habitRow = await _rowByPublicId(db, 'habits', publicId);
    final habitLocalId = habitRow['id'] as int;
    final day = _dateKey(DateTime.now())!;
    final rows = await db.query(
      'habit_logs',
      where: 'habit_id = ? AND date = ?',
      whereArgs: [habitLocalId, day],
    );
    for (final row in rows) {
      final localLogId = row['id'] as int;
      final serverLogId = row['server_id'] as int?;
      if (serverLogId == null) {
        await db.delete(
          'sync_queue',
          where: 'entity_type = ? AND entity_local_id = ?',
          whereArgs: ['habit_logs', localLogId],
        );
      }
      await db.delete('habit_logs', where: 'id = ?', whereArgs: [localLogId]);
    }
    if (habitRow['server_id'] != null) {
      await SyncService().enqueue(
        entityType: 'habits',
        entityLocalId: habitLocalId,
        entityServerId: habitRow['server_id'] as int?,
        operation: 'uncheck_today',
      );
    }
    return {'checked': false};
  }

  Future<Map<String, dynamic>> _habitByPublicId(int publicId) async {
    final habits = await getHabits();
    return habits.firstWhere((item) => item['id'] == publicId);
  }

  Future<Task> _taskByLocalId(Database db, int localId) async {
    final row = (await db.query(
      'tasks',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [localId],
      limit: 1,
    )).single;
    return _taskFromRow(db, row);
  }

  Future<Task> _taskFromRow(Database db, Map<String, Object?> row) async {
    final localId = row['id'] as int;
    final publicListId =
        await _publicForeignId(db, 'lists', row['list_id'] as int?);
    TodoList? list;
    if (row['list_id'] != null) {
      final listRows = await db.query(
        'lists',
        where: 'id = ?',
        whereArgs: [row['list_id']],
        limit: 1,
      );
      if (listRows.isNotEmpty) list = _listFromRow(listRows.first);
    }
    final tagRows = await db.rawQuery(
      '''SELECT t.* FROM tags t
         INNER JOIN task_tags tt ON t.id = tt.tag_id
         WHERE tt.task_id = ?''',
      [localId],
    );
    final tags = <Tag>[];
    for (final tag in tagRows) {
      tags.add(Tag(
        id: _publicId(tag),
        name: tag['name'] as String? ?? '',
        color: tag['color'] as String? ?? '#0075de',
        createdAt: _instant(tag['created_at']) ?? DateTime.now(),
      ));
    }
    return Task(
      id: _publicId(row),
      listId: publicListId ?? 0,
      title: row['title'] as String? ?? '',
      description: row['description'] as String?,
      priority: row['priority'] as String? ?? 'none',
      dueDate: row['due_date'] == null
          ? null
          : DateTime.tryParse(row['due_date'].toString()),
      dueTime: row['due_time'] as String?,
      isCompleted: (row['is_completed'] as int? ?? 0) == 1,
      completedAt: _instant(row['completed_at']),
      repeatType: row['repeat_type'] as String? ?? 'none',
      repeatInterval: row['repeat_interval'] as int? ?? 1,
      repeatDays: row['repeat_days'] as String? ?? '',
      reminderAt: _instant(row['reminder_at']),
      reminderAdvanceMinutes: row['reminder_advance_minutes'] as int? ?? 0,
      createdAt: _instant(row['created_at']) ?? DateTime.now(),
      list: list,
      tags: tags,
      systemTagId:
          await _publicForeignId(db, 'system_tags', row['system_tag_id'] as int?),
      taskType: row['task_type'] as String? ?? 'daily',
      moodBefore: row['mood_before'] as int? ?? 0,
      moodAfter: row['mood_after'] as int? ?? 0,
      isMilestone: (row['is_milestone'] as int? ?? 0) == 1,
      relatedQuestId:
          await _publicForeignId(db, 'tasks', row['related_quest_id'] as int?),
      obsidianLink: row['obsidian_link'] as String? ?? '',
      outputLevel: row['output_level'] as String? ?? '',
      version: row['version'] as int? ?? 1,
      syncStatus: row['sync_status'] as String? ?? 'synced',
      lastModified: _instant(row['last_modified']),
      deviceId: row['device_id'] as String? ?? '',
    );
  }

  TodoList _listFromRow(Map<String, Object?> row) => TodoList(
        id: _publicId(row),
        serverId: row['server_id'] as int?,
        name: row['name'] as String? ?? '',
        icon: row['icon'] as String? ?? '📋',
        color: row['color'] as String? ?? '#1890ff',
        isInbox: (row['is_inbox'] as int? ?? 0) == 1,
        createdAt: _instant(row['created_at']) ?? DateTime.now(),
      );

  Future<Map<String, dynamic>> _habitLogMap(
    Database db,
    Map<String, Object?> row,
  ) async =>
      {
        'id': _publicId(row),
        'habit_id':
            await _publicForeignId(db, 'habits', row['habit_id'] as int?),
        'date': row['date'],
        'period': row['period'] ?? '',
        'duration_min': row['duration_min'] ?? 0,
        'note': row['note'] ?? '',
        'task_id': await _publicForeignId(db, 'tasks', row['task_id'] as int?),
        'created_at': row['created_at'],
      };

  Future<void> _replaceTaskTags(
    Database db,
    int taskLocalId,
    List<int> publicTagIds,
  ) async {
    await db.delete('task_tags', where: 'task_id = ?', whereArgs: [taskLocalId]);
    for (final publicTagId in publicTagIds) {
      final tagLocalId = await _localId(db, 'tags', publicTagId);
      await db.insert(
        'task_tags',
        {'task_id': taskLocalId, 'tag_id': tagLocalId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<Map<String, Object?>> _rowByPublicId(
    Database db,
    String table,
    int publicId,
  ) async {
    final rows = publicId < 0
        ? await db.query(
            table,
            where: 'id = ?',
            whereArgs: [-publicId],
            limit: 1,
          )
        : await db.query(
            table,
            where: 'server_id = ?',
            whereArgs: [publicId],
            limit: 1,
          );
    if (rows.isEmpty) {
      throw StateError('Cloud cache $table not found: $publicId');
    }
    return rows.first;
  }

  Future<int> _localId(Database db, String table, int publicId) async {
    final row = await _rowByPublicId(db, table, publicId);
    return row['id'] as int;
  }

  Future<int?> _publicForeignId(
    Database db,
    String table,
    int? localId,
  ) async {
    if (localId == null) return null;
    final rows = await db.query(
      table,
      columns: ['id', 'server_id'],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    return rows.isEmpty ? null : _publicId(rows.first);
  }

  int _publicId(Map<String, Object?> row) =>
      (row['server_id'] as int?) ?? -(row['id'] as int);

  DateTime? _instant(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

  String? _dateKey(DateTime? value) => value == null
      ? null
      : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> _jsonMap(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  String _now() => DateTime.now().toUtc().toIso8601String();
}
