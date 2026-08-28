import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/task.dart';
import '../models/todo_list.dart';
import '../models/tag.dart';
import '../models/subtask.dart';
import '../repositories/cloud_cache_repository.dart';
import '../repositories/cloud_reference_cache_repository.dart';
import 'api/task_api.dart';
import 'api_service.dart';
import 'cloud_sync_coordinator.dart';
import 'cloud_task_completion_cache.dart';
import 'data_source.dart';

class CloudApiService implements ApiDataSource {
  final CloudCacheRepository _cache = CloudCacheRepository();
  final CloudReferenceCacheRepository _references =
      CloudReferenceCacheRepository();
  final CloudTaskCompletionCache _completionCache = CloudTaskCompletionCache();

  Future<T> _readThrough<T>(
    Future<T> Function() remote,
    Future<T> Function() cached,
  ) async {
    try {
      return await remote();
    } catch (error) {
      if (!_isTransientNetworkError(error)) rethrow;
      return cached();
    }
  }

  Future<T> _writeThrough<T>(
    Future<T> Function() remote,
    Future<T> Function() cached,
  ) async {
    try {
      final result = await remote();
      _refreshCacheSoon();
      return result;
    } catch (error) {
      if (!_isTransientNetworkError(error)) rethrow;
      return cached();
    }
  }

  Future<void> _writeThroughVoid(
    Future<void> Function() remote,
    Future<void> Function() cached,
  ) async {
    try {
      await remote();
      _refreshCacheSoon();
    } catch (error) {
      if (!_isTransientNetworkError(error)) rethrow;
      await cached();
    }
  }

  void _refreshCacheSoon() {
    unawaited(CloudSyncCoordinator().syncNow());
  }

  bool _containsTemporaryId(Iterable<int?> ids) =>
      ids.any((id) => id != null && id < 0);

  bool _isTransientNetworkError(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException) {
      return true;
    }
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('timeoutexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('network is unreachable') ||
        text.contains('clientexception');
  }

  @override
  Future<List<TodoList>> getLists() =>
      _readThrough(ApiService.getLists, _cache.getLists);

  @override
  Future<TodoList> createList({
    required String name,
    String icon = '📁',
    String color = '#1890ff',
    bool isInbox = false,
  }) =>
      _writeThrough(
        () => ApiService.createList(
          name: name,
          icon: icon,
          color: color,
          isInbox: isInbox,
        ),
        () => _cache.createList(
          name: name,
          icon: icon,
          color: color,
          isInbox: isInbox,
        ),
      );

  @override
  Future<TodoList> updateList({
    required int id,
    String? name,
    String? icon,
    String? color,
  }) {
    if (id < 0) {
      return _cache.updateList(
        publicId: id,
        name: name,
        icon: icon,
        color: color,
      );
    }
    return _writeThrough(
      () => ApiService.updateList(
        id: id,
        name: name,
        icon: icon,
        color: color,
      ),
      () => _cache.updateList(
        publicId: id,
        name: name,
        icon: icon,
        color: color,
      ),
    );
  }

  @override
  Future<void> deleteList(int id) {
    if (id < 0) return _cache.deleteList(id);
    return _writeThroughVoid(
      () => ApiService.deleteList(id),
      () => _cache.deleteList(id),
    );
  }

  @override
  Future<List<Task>> getTasks(int listId) {
    if (listId < 0) return _cache.getTasks(listId);
    return _readThrough(
      () => TaskApi.getTasks(listId),
      () => _cache.getTasks(listId),
    );
  }

  @override
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
  }) {
    Future<Task> cached() => _cache.createTask(
          listId: listId,
          title: title,
          description: description,
          priority: priority,
          dueDate: dueDate,
          dueTime: dueTime,
          repeatType: repeatType,
          repeatInterval: repeatInterval,
          repeatDays: repeatDays,
          reminderAt: reminderAt,
          reminderAdvanceMinutes: reminderAdvanceMinutes,
          tagIds: tagIds,
          systemTagId: systemTagId,
          taskType: taskType,
          moodBefore: moodBefore,
          moodAfter: moodAfter,
          isMilestone: isMilestone,
          relatedQuestId: relatedQuestId,
          obsidianLink: obsidianLink,
          outputLevel: outputLevel,
        );

    final refs = <int?>[
      listId,
      systemTagId,
      relatedQuestId,
      ...?tagIds,
    ];
    if (_containsTemporaryId(refs)) return cached();

    return _writeThrough(
      () => TaskApi.createTask(
        listId: listId,
        title: title,
        description: description,
        priority: priority,
        dueDate: dueDate,
        dueTime: dueTime,
        repeatType: repeatType,
        repeatInterval: repeatInterval,
        repeatDays: repeatDays,
        reminderAt: reminderAt,
        reminderAdvanceMinutes: reminderAdvanceMinutes,
        tagIds: tagIds,
        systemTagId: systemTagId,
        taskType: taskType,
        moodBefore: moodBefore,
        moodAfter: moodAfter,
        isMilestone: isMilestone,
        relatedQuestId: relatedQuestId,
        obsidianLink: obsidianLink,
        outputLevel: outputLevel,
      ),
      cached,
    );
  }

  @override
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
  }) {
    Future<Task> cached() => _cache.updateTask(
          taskId: taskId,
          listId: listId,
          title: title,
          description: description,
          priority: priority,
          dueDate: dueDate,
          dueTime: dueTime,
          repeatType: repeatType,
          repeatInterval: repeatInterval,
          repeatDays: repeatDays,
          reminderAt: reminderAt,
          reminderAdvanceMinutes: reminderAdvanceMinutes,
          tagIds: tagIds,
          systemTagId: systemTagId,
          taskType: taskType,
          moodBefore: moodBefore,
          moodAfter: moodAfter,
          isMilestone: isMilestone,
          relatedQuestId: relatedQuestId,
          obsidianLink: obsidianLink,
          outputLevel: outputLevel,
        );

    final refs = <int?>[
      taskId,
      listId,
      systemTagId,
      relatedQuestId,
      ...?tagIds,
    ];
    if (_containsTemporaryId(refs)) return cached();

    return _writeThrough(
      () => TaskApi.updateTask(
        taskId: taskId,
        listId: listId,
        title: title,
        description: description,
        priority: priority,
        dueDate: dueDate,
        dueTime: dueTime,
        repeatType: repeatType,
        repeatInterval: repeatInterval,
        repeatDays: repeatDays,
        reminderAt: reminderAt,
        reminderAdvanceMinutes: reminderAdvanceMinutes,
        tagIds: tagIds,
        systemTagId: systemTagId,
        taskType: taskType,
        moodBefore: moodBefore,
        moodAfter: moodAfter,
        isMilestone: isMilestone,
        relatedQuestId: relatedQuestId,
        obsidianLink: obsidianLink,
        outputLevel: outputLevel,
      ),
      cached,
    );
  }

  @override
  Future<Task> completeTask(int taskId) {
    if (taskId < 0) return _completionCache.toggle(taskId);
    return _writeThrough(
      () => TaskApi.completeTask(taskId),
      () => _completionCache.toggle(taskId),
    );
  }

  @override
  Future<void> deleteTask(int taskId) {
    if (taskId < 0) return _cache.deleteTask(taskId);
    return _writeThroughVoid(
      () => TaskApi.deleteTask(taskId),
      () => _cache.deleteTask(taskId),
    );
  }

  @override
  Future<List<Task>> getTodayTasks() =>
      _readThrough(TaskApi.getTodayTasks, _cache.getTodayTasks);

  @override
  Future<List<Task>> searchTasks(String query) => _readThrough(
        () => TaskApi.searchTasks(query),
        () => _cache.searchTasks(query),
      );

  @override
  Future<Task> postponeTask(int taskId) => TaskApi.postponeTask(taskId);

  @override
  Future<List<Task>> getTasksForMonth(int year, int month) => _readThrough(
        () => TaskApi.getTasksForMonth(year, month),
        () => _cache.getTasksForMonth(year, month),
      );

  @override
  Future<List<Task>> getCompletedTasks() =>
      _readThrough(TaskApi.getCompletedTasks, _cache.getCompletedTasks);

  @override
  Future<List<Task>> getAllTasks() =>
      _readThrough(TaskApi.getAllTasks, _cache.getAllTasks);

  // Subtask 目前没有纳入 Cloud Cache schema，保持明确的在线能力。
  @override
  Future<List<Subtask>> getSubtasks(int taskId) => ApiService.getSubtasks(taskId);
  @override
  Future<Subtask> createSubtask(int taskId, String title) =>
      ApiService.createSubtask(taskId, title);
  @override
  Future<Subtask> toggleSubtask(int taskId, int subtaskId) =>
      ApiService.toggleSubtask(taskId, subtaskId);
  @override
  Future<void> deleteSubtask(int taskId, int subtaskId) =>
      ApiService.deleteSubtask(taskId, subtaskId);
  @override
  Future<Map<String, int>> getSubtaskProgress(int taskId) =>
      ApiService.getSubtaskProgress(taskId);

  // Tag 暂不开放离线编辑；读取在网络故障时回退到 Cloud Cache。
  @override
  Future<List<Tag>> getTags() =>
      _readThrough(ApiService.getTags, _references.getTags);
  @override
  Future<Tag> createTag({required String name, required String color}) =>
      ApiService.createTag(name: name, color: color);
  @override
  Future<Tag> updateTag({required int id, String? name, String? color}) =>
      ApiService.updateTag(id: id, name: name, color: color);
  @override
  Future<void> deleteTag(int tagId) => ApiService.deleteTag(tagId);
  @override
  Future<List<Task>> getTasksByTag(int tagId) => ApiService.getTasksByTag(tagId);

  @override
  Future<List<Map<String, dynamic>>> getHabits() =>
      _readThrough(ApiService.getHabits, _cache.getHabits);

  @override
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
  }) {
    Future<Map<String, dynamic>> cached() => _cache.createHabit(
          name: name,
          icon: icon,
          color: color,
          frequency: frequency,
          targetDays: targetDays,
          systemTagId: systemTagId,
          preferredPeriod: preferredPeriod,
          durationMin: durationMin,
          generateTask: generateTask,
          showCheckinDialog: showCheckinDialog,
          specificTime: specificTime,
          reminderAt: reminderAt,
        );
    if (systemTagId != null && systemTagId < 0) return cached();
    return _writeThrough(
      () => ApiService.createHabit(
        name: name,
        icon: icon,
        color: color,
        frequency: frequency,
        targetDays: targetDays,
        systemTagId: systemTagId,
        preferredPeriod: preferredPeriod,
        durationMin: durationMin,
        generateTask: generateTask,
        showCheckinDialog: showCheckinDialog,
        specificTime: specificTime,
        reminderAt: reminderAt,
      ),
      cached,
    );
  }

  @override
  Future<void> updateHabit(int habitId, Map<String, dynamic> data) {
    final systemTagId = data['system_tag_id'] as int?;
    if (habitId < 0 || (systemTagId != null && systemTagId < 0)) {
      return _cache.updateHabit(habitId, data);
    }
    return _writeThroughVoid(
      () => ApiService.updateHabit(habitId, data),
      () => _cache.updateHabit(habitId, data),
    );
  }

  @override
  Future<Map<String, dynamic>> checkInHabit(
    int habitId, {
    String note = '',
    String? date,
    int? durationMin,
    String? period,
  }) {
    Future<Map<String, dynamic>> cached() => _cache.checkInHabit(
          habitId,
          note: note,
          date: date,
          durationMin: durationMin,
          period: period,
        );
    if (habitId < 0) return cached();
    return _writeThrough(
      () => ApiService.checkInHabit(
        habitId,
        note: note,
        date: date,
        durationMin: durationMin,
        period: period,
      ),
      cached,
    );
  }

  /// 服务端取消打卡当前只能表达“今天”。跨日离线同步会丢失目标日期，
  /// 因此 server-backed Habit 暂不做离线降级；纯离线新建 Habit 可安全撤销本地打卡。
  @override
  Future<Map<String, dynamic>> uncheckInHabit(int habitId) {
    if (habitId < 0) return _cache.uncheckInHabit(habitId);
    return ApiService.uncheckInHabit(habitId);
  }

  @override
  Future<Map<String, dynamic>> getHabitLogs(int habitId, {String? month}) {
    if (habitId < 0) return _cache.getHabitLogs(habitId, month: month);
    return _readThrough(
      () => ApiService.getHabitLogs(habitId, month: month),
      () => _cache.getHabitLogs(habitId, month: month),
    );
  }

  @override
  Future<void> deleteHabit(int habitId) {
    if (habitId < 0) return _cache.deleteHabit(habitId);
    return _writeThroughVoid(
      () => ApiService.deleteHabit(habitId),
      () => _cache.deleteHabit(habitId),
    );
  }

  // ObservationTag 暂保持在线编辑；读取可回退到 Cloud Cache。
  @override
  Future<List<Map<String, dynamic>>> getSystemTags() =>
      _readThrough(ApiService.getSystemTags, _references.getSystemTagMaps);
  @override
  Future<Map<String, dynamic>> createSystemTag({
    required String name,
    required String icon,
    required String color,
  }) =>
      ApiService.createSystemTag(name: name, icon: icon, color: color);
  @override
  Future<Map<String, dynamic>> updateSystemTag(
    int id, {
    String? icon,
    String? color,
  }) =>
      ApiService.updateSystemTag(id, icon: icon, color: color);
  @override
  Future<void> deleteSystemTag(int id) => ApiService.deleteSystemTag(id);

  @override
  Future<Map<String, dynamic>> getInbox() => ApiService.getInbox();
  @override
  Future<Task> quickAddToInbox(String title, {int? systemTagId}) =>
      ApiService.quickAddToInbox(title, systemTagId: systemTagId);
  @override
  Future<Task> moveInboxTask(int taskId, int listId) =>
      ApiService.moveInboxTask(taskId, listId);
  @override
  Future<int> getInboxCount() => ApiService.getInboxCount();
}
