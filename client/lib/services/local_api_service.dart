import '../models/task.dart';
import '../models/todo_list.dart';
import '../models/tag.dart';
import '../models/subtask.dart';
import '../repositories/local_list_repository.dart';
import '../repositories/local_task_repository.dart';
import '../repositories/local_tag_repository.dart';
import '../repositories/local_habit_repository.dart';
import 'data_source.dart';

/// 本地 API 服务 - 使用 SQLite 仓储实现数据源接口。
///
/// Local Data Mode 不依赖 Slowlight Server，因此这里禁止创建 server sync queue。
class LocalApiService implements ApiDataSource {
  final _listRepo = LocalListRepository();
  final _taskRepo = LocalTaskRepository();
  final _tagRepo = LocalTagRepository();
  final _habitRepo = LocalHabitRepository();

  // ===== 清单 =====

  @override
  Future<List<TodoList>> getLists() => _listRepo.getAll();

  @override
  Future<TodoList> createList({
    required String name,
    String icon = '📁',
    String color = '#1890ff',
    bool isInbox = false,
  }) =>
      _listRepo.create(name: name, icon: icon, color: color, isInbox: isInbox);

  @override
  Future<TodoList> updateList({
    required int id,
    String? name,
    String? icon,
    String? color,
  }) =>
      _listRepo.update(id: id, name: name, icon: icon, color: color);

  @override
  Future<void> deleteList(int id) => _listRepo.delete(id);

  // ===== 任务 =====

  @override
  Future<List<Task>> getTasks(int listId) => _taskRepo.getByListId(listId);

  Future<Task> getTask(int taskId) async {
    final task = await _taskRepo.getById(taskId);
    if (task == null) throw Exception('任务不存在');
    return task;
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
  }) =>
      _taskRepo.create(
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
  }) =>
      _taskRepo.update(
        id: taskId,
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

  @override
  Future<Task> completeTask(int taskId) => _taskRepo.complete(taskId);

  @override
  Future<void> deleteTask(int taskId) => _taskRepo.delete(taskId);

  @override
  Future<List<Task>> getTodayTasks() => _taskRepo.getTodayTasks();

  @override
  Future<List<Task>> searchTasks(String query) => _taskRepo.search(query);

  @override
  Future<Task> postponeTask(int taskId) => _taskRepo.postpone(taskId);

  @override
  Future<List<Task>> getTasksForMonth(int year, int month) =>
      _taskRepo.getForMonth(year, month);

  @override
  Future<List<Task>> getCompletedTasks() => _taskRepo.getCompleted();

  @override
  Future<List<Task>> getAllTasks() => _taskRepo.getAll();

  // ===== 子任务 =====

  @override
  Future<List<Subtask>> getSubtasks(int taskId) =>
      _taskRepo.getSubtasks(taskId);

  @override
  Future<Subtask> createSubtask(int taskId, String title) =>
      _taskRepo.createSubtask(taskId, title);

  @override
  Future<Subtask> toggleSubtask(int taskId, int subtaskId) =>
      _taskRepo.toggleSubtask(taskId, subtaskId);

  @override
  Future<void> deleteSubtask(int taskId, int subtaskId) =>
      _taskRepo.deleteSubtask(taskId, subtaskId);

  @override
  Future<Map<String, int>> getSubtaskProgress(int taskId) =>
      _taskRepo.getSubtaskProgress(taskId);

  // ===== 标签 =====

  @override
  Future<List<Tag>> getTags() => _tagRepo.getAll();

  @override
  Future<Tag> createTag({required String name, required String color}) =>
      _tagRepo.create(name: name, color: color);

  @override
  Future<Tag> updateTag({required int id, String? name, String? color}) =>
      _tagRepo.update(id: id, name: name, color: color);

  @override
  Future<void> deleteTag(int tagId) => _tagRepo.delete(tagId);

  @override
  Future<List<Task>> getTasksByTag(int tagId) async {
    final taskIds = await _tagRepo.getTaskIdsByTag(tagId);
    final allTasks = await _taskRepo.getAll();
    return allTasks.where((t) => taskIds.contains(t.id)).toList();
  }

  // ===== 习惯 =====

  @override
  Future<List<Map<String, dynamic>>> getHabits() => _habitRepo.getAll();

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
  }) =>
      _habitRepo.create(
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

  @override
  Future<void> updateHabit(int habitId, Map<String, dynamic> data) async {
    await _habitRepo.update(
      habitId,
      name: data['name'] as String?,
      icon: data['icon'] as String?,
      color: data['color'] as String?,
      frequency: data['frequency'] as String?,
      targetDays: data['target_days'] as int?,
      systemTagId: data['system_tag_id'] as int?,
      setSystemTag: data.containsKey('system_tag_id'),
      preferredPeriod: data['preferred_period'] as String?,
      durationMin: data['duration_min'] as int?,
      generateTask: data['generate_task'] as bool?,
      showCheckinDialog: data['show_checkin_dialog'] as bool?,
      specificTime: data['specific_time'] as String?,
      reminderAt: data['reminder_at'] is Map
          ? Map<String, dynamic>.from(data['reminder_at'] as Map)
          : null,
    );
  }

  @override
  Future<Map<String, dynamic>> checkInHabit(
    int habitId, {
    String note = '',
    String? date,
    int? durationMin,
    String? period,
  }) =>
      _habitRepo.checkIn(
        habitId,
        note: note,
        date: date,
        durationMin: durationMin,
        period: period,
      );

  @override
  Future<Map<String, dynamic>> uncheckInHabit(int habitId) =>
      _habitRepo.uncheckIn(habitId);

  @override
  Future<Map<String, dynamic>> getHabitLogs(int habitId, {String? month}) =>
      _habitRepo.getLogs(habitId, month: month);

  Future<Map<String, dynamic>> updateHabitLog(
          int habitId, int logId, Map<String, dynamic> data) =>
      _habitRepo.updateLog(habitId, logId, data);

  @override
  Future<void> deleteHabit(int habitId) => _habitRepo.delete(habitId);

  // ===== 系统标签 =====

  @override
  Future<List<Map<String, dynamic>>> getSystemTags() =>
      _habitRepo.getSystemTags();

  @override
  Future<Map<String, dynamic>> createSystemTag({
    required String name,
    required String icon,
    required String color,
  }) =>
      _habitRepo.createSystemTag(name: name, icon: icon, color: color);

  @override
  Future<Map<String, dynamic>> updateSystemTag(
    int id, {
    String? icon,
    String? color,
  }) =>
      _habitRepo.updateSystemTag(id, icon: icon, color: color);

  @override
  Future<void> deleteSystemTag(int id) => _habitRepo.deleteSystemTag(id);

  // ===== 收集箱 =====

  @override
  Future<Map<String, dynamic>> getInbox() async {
    final lists = await _listRepo.getAll();
    final inboxList = lists.where((l) => l.isInbox).toList();
    if (inboxList.isEmpty) return {'tasks': [], 'count': 0};
    final tasks = await _taskRepo.getByListId(inboxList.first.id);
    return {'tasks': tasks, 'count': tasks.length};
  }

  @override
  Future<Task> quickAddToInbox(String title, {int? systemTagId}) async {
    final lists = await _listRepo.getAll();
    var inboxList = lists.where((l) => l.isInbox).toList();
    if (inboxList.isEmpty && systemTagId != null && lists.isNotEmpty) {
      inboxList = [lists.first];
    }
    if (inboxList.isEmpty) {
      final created = await _listRepo.create(
        name: '收集箱',
        icon: '📥',
        color: '#722ed1',
        isInbox: true,
      );
      inboxList = [created];
    }
    return _taskRepo.create(
      listId: inboxList.first.id,
      title: title,
      systemTagId: systemTagId,
    );
  }

  @override
  Future<Task> moveInboxTask(int taskId, int listId) async {
    final task = await _taskRepo.getById(taskId);
    if (task == null) throw Exception('任务不存在');
    return _taskRepo.update(
      id: taskId,
      listId: listId,
      title: task.title,
      description: task.description,
      priority: task.priority,
      dueDate: task.dueDate,
      dueTime: task.dueTime,
      repeatType: task.repeatType,
      repeatInterval: task.repeatInterval,
      repeatDays: task.repeatDays,
      reminderAt: task.reminderAt,
      reminderAdvanceMinutes: task.reminderAdvanceMinutes,
      systemTagId: task.systemTagId,
      taskType: task.taskType,
      moodBefore: task.moodBefore,
      moodAfter: task.moodAfter,
      isMilestone: task.isMilestone,
      relatedQuestId: task.relatedQuestId,
      obsidianLink: task.obsidianLink,
      outputLevel: task.outputLevel,
    );
  }

  @override
  Future<int> getInboxCount() async {
    final inbox = await getInbox();
    return inbox['count'] as int;
  }
}
