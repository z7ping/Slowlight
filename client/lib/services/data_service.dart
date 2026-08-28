import '../models/task.dart';
import '../models/todo_list.dart';
import '../models/tag.dart';
import '../repositories/task_repository.dart';
import '../repositories/habit_repository.dart';
import '../repositories/list_repository.dart';
import '../repositories/tag_repository.dart';
import '../repositories/local_task_repository.dart';
import '../repositories/local_task_completion.dart';
import 'api_service.dart';
import 'data_mode_manager.dart';

/// Slowlight 兼容数据门面。
///
/// 新代码优先直接依赖领域 Repository；本类只给遗留页面提供稳定入口。
/// Data Mode 的选择由 Repository 负责，上层不应再绕过 Repository 直接操作
/// TaskApi / SQLite。
class DataService {
  static final DataService _instance = DataService._();
  factory DataService() => _instance;
  DataService._();

  final TaskRepository taskRepository = TaskRepository();
  final HabitRepository habitRepository = HabitRepository();
  final ListRepository listRepository = ListRepository();
  final TagRepository tagRepository = TagRepository();

  final LocalTaskRepository _localTaskRepository = LocalTaskRepository();

  int _effectiveId(int primaryId, int? serverId) {
    if (DataModeManager().isCloud && serverId != null) return serverId;
    return primaryId;
  }

  // ═══════════════════════════════════════
  // 任务
  // ═══════════════════════════════════════

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
  }) =>
      taskRepository.create(
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

  Future<Task> updateTask({
    required int localId,
    int? serverId,
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
  }) =>
      taskRepository.updateTask(
        taskId: _effectiveId(localId, serverId),
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

  Future<Task> completeTask(int localId, int? serverId) =>
      taskRepository.completeTask(_effectiveId(localId, serverId));

  Future<Task> uncompleteTask(int localId, int? serverId) {
    if (DataModeManager().isLocal) {
      return _localTaskRepository.uncomplete(localId);
    }
    // Cloud /complete 目前是 toggle；调用方只对“已完成任务”进入该路径。
    return taskRepository.completeTask(_effectiveId(localId, serverId));
  }

  Future<void> deleteTask(int localId, int? serverId) =>
      taskRepository.deleteTask(_effectiveId(localId, serverId));

  Future<Task> postponeTask(int localId, int? serverId) =>
      taskRepository.postponeTask(_effectiveId(localId, serverId));

  Future<List<Task>> getTodayTasks() => taskRepository.getTodayTasks();
  Future<List<Task>> getTasksByListId(int listId) =>
      taskRepository.getTasksByListId(listId);
  Future<List<Task>> getCompletedTasks() => taskRepository.getCompletedTasks();
  Future<List<Task>> getAllTasks() => taskRepository.getAll();
  Future<List<Task>> searchTasks(String query) => taskRepository.search(query);

  // ═══════════════════════════════════════
  // 清单
  // ═══════════════════════════════════════

  Future<TodoList> createList({
    required String name,
    String icon = '📋',
    String color = '#1890ff',
    bool isInbox = false,
  }) =>
      listRepository.createList(
        name: name,
        icon: icon,
        color: color,
        isInbox: isInbox,
      );

  Future<TodoList> updateList({
    required int localId,
    int? serverId,
    required String name,
    String icon = '📋',
    String color = '#1890ff',
  }) =>
      listRepository.updateList(
        id: _effectiveId(localId, serverId),
        name: name,
        icon: icon,
        color: color,
      );

  Future<void> deleteList(int localId, int? serverId) =>
      listRepository.deleteList(_effectiveId(localId, serverId));

  Future<List<TodoList>> getLists() => listRepository.getLists();

  // ═══════════════════════════════════════
  // 普通标签
  // ═══════════════════════════════════════

  Future<Tag> createTag({required String name, required String color}) =>
      tagRepository.createTag(name: name, color: color);

  Future<Tag> updateTag({
    required int id,
    String? name,
    String? color,
  }) =>
      tagRepository.updateTag(id: id, name: name, color: color);

  Future<void> deleteTag(int id) => tagRepository.deleteTag(id);
  Future<List<Tag>> getTags() => tagRepository.getTags();

  // ═══════════════════════════════════════
  // 习惯（兼容入口；后续继续强类型化）
  // ═══════════════════════════════════════

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
  }) =>
      ApiService.createHabit(
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

  Future<void> deleteHabit(int localId, int? serverId) =>
      habitRepository.deleteHabit(_effectiveId(localId, serverId));

  Future<Map<String, dynamic>> checkInHabit(
    int habitId, {
    String note = '',
    String? date,
    int? durationMin,
    String? period,
  }) =>
      habitRepository.checkInHabit(
        habitId,
        note: note,
        date: date,
        durationMin: durationMin,
        period: period,
      );

  Future<Map<String, dynamic>> uncheckInHabit(int habitId) =>
      habitRepository.uncheckInHabit(habitId);

  Future<List<Map<String, dynamic>>> getHabits() => habitRepository.getHabits();

  // ═══════════════════════════════════════
  // 收集箱（兼容入口）
  // ═══════════════════════════════════════

  Future<Task> quickAddToInbox(String title, {int? systemTagId}) =>
      ApiService.quickAddToInbox(title, systemTagId: systemTagId);
}
