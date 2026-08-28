import 'package:sqflite/sqflite.dart';

import '../db/local_db.dart';
import '../models/subtask.dart';
import '../models/tag.dart';
import '../models/task.dart';
import '../models/todo_list.dart';
import '../utils/local_time_boundary.dart';

/// Local Task 的 SQLite 实现。
///
/// 约定：
/// - instant（created/completed/updated/reminder）统一存 UTC；
/// - due_date 是用户日历日期，保持 YYYY-MM-DD；
/// - 外部调用经 TaskRepository，不直接依赖本实现。
class LocalTaskRepository {
  final _db = LocalDb();

  String _nowUtc() => LocalTimeBoundary.nowUtc().toIso8601String();

  String? _calendarDate(DateTime? value) => value == null
      ? null
      : '${value.year.toString().padLeft(4, '0')}-'
          '${value.month.toString().padLeft(2, '0')}-'
          '${value.day.toString().padLeft(2, '0')}';

  Future<List<Task>> getByListId(int listId) async {
    final db = await _db.database;
    final rows = await db.query(
      'tasks',
      where: 'list_id = ? AND deleted_at IS NULL',
      whereArgs: [listId],
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return Future.wait(rows.map((row) => _fromMapWithRelations(db, row)));
  }

  Future<List<Task>> getTodayTasks() async {
    final db = await _db.database;
    final date = LocalTimeBoundary.dateKey(DateTime.now());
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
    return Future.wait(rows.map((row) => _fromMapWithRelations(db, row)));
  }

  Future<List<Task>> getAllActive() async {
    final db = await _db.database;
    final rows = await db.query(
      'tasks',
      where: 'deleted_at IS NULL AND is_completed = 0',
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return Future.wait(rows.map((row) => _fromMapWithRelations(db, row)));
  }

  Future<List<Task>> getCompleted() async {
    final db = await _db.database;
    final rows = await db.query(
      'tasks',
      where: 'deleted_at IS NULL AND is_completed = 1',
      orderBy: 'completed_at DESC',
    );
    return Future.wait(rows.map((row) => _fromMapWithRelations(db, row)));
  }

  Future<List<Task>> getAll() async {
    final db = await _db.database;
    final rows = await db.query(
      'tasks',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
    return Future.wait(rows.map((row) => _fromMapWithRelations(db, row)));
  }

  Future<List<Task>> getForMonth(int year, int month) async {
    final db = await _db.database;
    final monthText = month.toString().padLeft(2, '0');
    final rows = await db.query(
      'tasks',
      where: 'deleted_at IS NULL AND due_date LIKE ?',
      whereArgs: ['$year-$monthText%'],
      orderBy: 'due_date ASC, sort_order ASC',
    );
    return Future.wait(rows.map((row) => _fromMapWithRelations(db, row)));
  }

  Future<List<Task>> search(String query) async {
    final value = query.trim();
    if (value.isEmpty) return const [];
    final db = await _db.database;
    final rows = await db.query(
      'tasks',
      where: 'deleted_at IS NULL AND title LIKE ?',
      whereArgs: ['%$value%'],
      orderBy: 'created_at DESC',
    );
    return Future.wait(rows.map((row) => _fromMapWithRelations(db, row)));
  }

  Future<Task?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'tasks',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromMapWithRelations(db, rows.first);
  }

  Future<Task> create({
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
    int? systemTagId,
    List<int>? tagIds,
    String taskType = 'daily',
    int moodBefore = 0,
    int moodAfter = 0,
    bool isMilestone = false,
    int? relatedQuestId,
    String obsidianLink = '',
    String outputLevel = '',
  }) async {
    final db = await _db.database;
    final now = _nowUtc();
    final id = await db.transaction((txn) async {
      final taskId = await txn.insert('tasks', {
        'list_id': listId,
        'title': title,
        'description': description ?? '',
        'priority': priority,
        'due_date': _calendarDate(dueDate),
        'due_time': dueTime,
        'repeat_type': repeatType,
        'repeat_interval': repeatInterval,
        'repeat_days': repeatDays,
        'reminder_at': reminderAt?.toUtc().toIso8601String(),
        'reminder_advance_minutes': reminderAdvanceMinutes,
        'system_tag_id': systemTagId,
        'task_type': taskType,
        'mood_before': moodBefore,
        'mood_after': moodAfter,
        'is_milestone': isMilestone ? 1 : 0,
        'related_quest_id': relatedQuestId,
        'obsidian_link': obsidianLink,
        'output_level': outputLevel,
        'created_at': now,
        'updated_at': now,
      });
      for (final tagId in tagIds ?? const <int>[]) {
        await txn.insert('task_tags', {'task_id': taskId, 'tag_id': tagId});
      }
      return taskId;
    });
    final result = await getById(id);
    if (result == null) throw Exception('创建任务失败');
    return result;
  }

  Future<Task> update({
    required int id,
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
    int? systemTagId,
    List<int>? tagIds,
    String taskType = 'daily',
    int moodBefore = 0,
    int moodAfter = 0,
    bool isMilestone = false,
    int? relatedQuestId,
    String obsidianLink = '',
    String outputLevel = '',
  }) async {
    final db = await _db.database;
    final now = _nowUtc();
    await db.transaction((txn) async {
      await txn.update(
        'tasks',
        {
          'list_id': listId,
          'title': title,
          'description': description ?? '',
          'priority': priority,
          'due_date': _calendarDate(dueDate),
          'due_time': dueTime,
          'repeat_type': repeatType,
          'repeat_interval': repeatInterval,
          'repeat_days': repeatDays,
          'reminder_at': reminderAt?.toUtc().toIso8601String(),
          'reminder_advance_minutes': reminderAdvanceMinutes,
          'system_tag_id': systemTagId,
          'task_type': taskType,
          'mood_before': moodBefore,
          'mood_after': moodAfter,
          'is_milestone': isMilestone ? 1 : 0,
          'related_quest_id': relatedQuestId,
          'obsidian_link': obsidianLink,
          'output_level': outputLevel,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (tagIds != null) {
        await txn.delete('task_tags', where: 'task_id = ?', whereArgs: [id]);
        for (final tagId in tagIds) {
          await txn.insert('task_tags', {'task_id': id, 'tag_id': tagId});
        }
      }
    });
    final result = await getById(id);
    if (result == null) throw Exception('更新任务失败');
    return result;
  }

  Future<Task> complete(int id) async {
    final db = await _db.database;
    final now = _nowUtc();
    await db.update(
      'tasks',
      {'is_completed': 1, 'completed_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    final result = await getById(id);
    if (result == null) throw Exception('完成任务失败');
    return result;
  }

  Future<Task> postpone(int id) async {
    final db = await _db.database;
    await db.update(
      'tasks',
      {
        'due_date': LocalTimeBoundary.dateKey(DateTime.now()),
        'updated_at': _nowUtc(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    final result = await getById(id);
    if (result == null) throw Exception('顺延任务失败');
    return result;
  }

  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.update(
      'tasks',
      {'deleted_at': _nowUtc()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Subtask>> getSubtasks(int taskId) async {
    final db = await _db.database;
    final rows = await db.query(
      'subtasks',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows.map(_subtaskFromMap).toList();
  }

  Future<Subtask> createSubtask(int taskId, String title) async {
    final db = await _db.database;
    final now = _nowUtc();
    final id = await db.insert('subtasks', {
      'task_id': taskId,
      'title': title,
      'created_at': now,
      'updated_at': now,
    });
    return Subtask(
      id: id,
      taskId: taskId,
      title: title,
      createdAt: DateTime.parse(now).toLocal(),
    );
  }

  Future<Subtask> toggleSubtask(int taskId, int subtaskId) async {
    final db = await _db.database;
    final rows = await db.query(
      'subtasks',
      where: 'id = ? AND task_id = ?',
      whereArgs: [subtaskId, taskId],
      limit: 1,
    );
    if (rows.isEmpty) throw Exception('子任务不存在');
    final current = rows.first;
    final next = (current['is_completed'] as int? ?? 0) == 1 ? 0 : 1;
    await db.update(
      'subtasks',
      {'is_completed': next, 'updated_at': _nowUtc()},
      where: 'id = ?',
      whereArgs: [subtaskId],
    );
    return Subtask(
      id: subtaskId,
      taskId: taskId,
      title: current['title'] as String,
      isCompleted: next == 1,
      sortOrder: current['sort_order'] as int? ?? 0,
      createdAt: DateTime.parse(current['created_at'] as String).toLocal(),
    );
  }

  Future<void> deleteSubtask(int taskId, int subtaskId) async {
    final db = await _db.database;
    await db.delete(
      'subtasks',
      where: 'id = ? AND task_id = ?',
      whereArgs: [subtaskId, taskId],
    );
  }

  Future<Map<String, int>> getSubtaskProgress(int taskId) async {
    final db = await _db.database;
    final total = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM subtasks WHERE task_id = ?',
            [taskId],
          ),
        ) ??
        0;
    final completed = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM subtasks WHERE task_id = ? AND is_completed = 1',
            [taskId],
          ),
        ) ??
        0;
    return {'total': total, 'completed': completed};
  }

  Subtask _subtaskFromMap(Map<String, dynamic> map) => Subtask(
        id: map['id'] as int,
        taskId: map['task_id'] as int,
        title: map['title'] as String,
        isCompleted: (map['is_completed'] as int? ?? 0) == 1,
        sortOrder: map['sort_order'] as int? ?? 0,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      );

  Future<Task> _fromMapWithRelations(
    Database db,
    Map<String, dynamic> map,
  ) async {
    final taskId = map['id'] as int;

    TodoList? list;
    final listId = map['list_id'] as int?;
    if (listId != null) {
      final listRows = await db.query(
        'lists',
        where: 'id = ?',
        whereArgs: [listId],
        limit: 1,
      );
      if (listRows.isNotEmpty) list = TodoList.fromJson(listRows.first);
    }

    final tagRows = await db.rawQuery(
      '''SELECT t.* FROM tags t
         INNER JOIN task_tags tt ON t.id = tt.tag_id
         WHERE tt.task_id = ?''',
      [taskId],
    );
    final tags = tagRows
        .map(
          (row) => Tag(
            id: row['id'] as int,
            name: row['name'] as String,
            color: row['color'] as String? ?? '#0075de',
            createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
          ),
        )
        .toList();

    final progress = await getSubtaskProgress(taskId);
    DateTime? instant(Object? raw) => raw == null
        ? null
        : DateTime.tryParse(raw.toString())?.toLocal();

    return Task(
      id: taskId,
      listId: listId ?? 0,
      title: map['title'] as String? ?? '',
      description: map['description'] as String?,
      priority: map['priority'] as String? ?? 'none',
      dueDate:
          map['due_date'] == null ? null : DateTime.parse(map['due_date'] as String),
      dueTime: map['due_time'] as String?,
      isCompleted: (map['is_completed'] as int? ?? 0) == 1,
      completedAt: instant(map['completed_at']),
      repeatType: map['repeat_type'] as String? ?? 'none',
      repeatInterval: map['repeat_interval'] as int? ?? 1,
      repeatDays: map['repeat_days'] as String? ?? '',
      reminderAt: instant(map['reminder_at']),
      reminderAdvanceMinutes:
          map['reminder_advance_minutes'] as int? ?? 0,
      createdAt: instant(map['created_at']) ?? DateTime.now(),
      list: list,
      subtaskCount: progress['total'] ?? 0,
      completedSubtask: progress['completed'] ?? 0,
      tags: tags,
      systemTagId: map['system_tag_id'] as int?,
      taskType: map['task_type'] as String? ?? 'daily',
      moodBefore: map['mood_before'] as int? ?? 0,
      moodAfter: map['mood_after'] as int? ?? 0,
      isMilestone: (map['is_milestone'] as int? ?? 0) == 1,
      relatedQuestId: map['related_quest_id'] as int?,
      obsidianLink: map['obsidian_link'] as String? ?? '',
      outputLevel: map['output_level'] as String? ?? '',
      version: map['version'] as int? ?? 1,
      syncStatus: map['sync_status'] as String? ?? 'synced',
      lastModified: instant(map['last_modified']),
      deviceId: map['device_id'] as String? ?? '',
    );
  }
}
