import '../models/task.dart';
import '../models/subtask.dart';
import '../services/cloud_api_service.dart';
import '../services/data_mode_manager.dart';
import '../services/data_source.dart';
import '../services/local_api_service.dart';

/// 任务 Repository，封装任务相关数据源切换逻辑
///
/// 通过 [ApiDataSource] 抽象层访问数据，自动适配本地模式（SQLite）
/// 和云端模式（Go 后端）。调用者无需关心底层数据源的实现细节。
class TaskRepository {
  final ApiDataSource? _fixedDataSource;

  TaskRepository({ApiDataSource? dataSource}) : _fixedDataSource = dataSource;

  ApiDataSource get _dataSource => _fixedDataSource ??
      (DataModeManager().isLocal ? LocalApiService() : CloudApiService());

  Future<List<Task>> getAll() => _dataSource.getAllTasks();
  Future<List<Task>> getTasksByListId(int listId) => _dataSource.getTasks(listId);
  Future<List<Task>> getTodayTasks() => _dataSource.getTodayTasks();
  Future<List<Task>> getCompletedTasks() => _dataSource.getCompletedTasks();
  Future<List<Task>> getTasksForMonth(int year, int month) =>
      _dataSource.getTasksForMonth(year, month);
  Future<List<Task>> search(String query) => _dataSource.searchTasks(query);

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
      _dataSource.createTask(
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
      _dataSource.updateTask(
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

  Future<Task> completeTask(int taskId) => _dataSource.completeTask(taskId);
  Future<Task> postponeTask(int taskId) => _dataSource.postponeTask(taskId);
  Future<void> deleteTask(int taskId) => _dataSource.deleteTask(taskId);

  Future<List<Subtask>> getSubtasks(int taskId) => _dataSource.getSubtasks(taskId);
  Future<Subtask> createSubtask(int taskId, String title) =>
      _dataSource.createSubtask(taskId, title);
  Future<Subtask> toggleSubtask(int taskId, int subtaskId) =>
      _dataSource.toggleSubtask(taskId, subtaskId);
  Future<void> deleteSubtask(int taskId, int subtaskId) =>
      _dataSource.deleteSubtask(taskId, subtaskId);
  Future<Map<String, int>> getSubtaskProgress(int taskId) =>
      _dataSource.getSubtaskProgress(taskId);
}
