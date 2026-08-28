import '../models/task.dart';
import '../models/todo_list.dart';
import '../models/tag.dart';
import '../models/subtask.dart';

/// 数据源抽象层 - 定义所有 CRUD 操作接口。
///
/// Local / Cloud 实现必须保持同一参数语义；可选的非空参数在接口层显式声明默认值，
/// 避免实现与调用方各自猜测默认值。
abstract class ApiDataSource {
  // ===== 清单 =====
  Future<List<TodoList>> getLists();
  Future<TodoList> createList({
    required String name,
    String icon = '📁',
    String color = '#1890ff',
    bool isInbox = false,
  });
  Future<TodoList> updateList({
    required int id,
    String? name,
    String? icon,
    String? color,
  });
  Future<void> deleteList(int id);

  // ===== 任务 =====
  Future<List<Task>> getTasks(int listId);
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
  });
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
  });
  Future<Task> completeTask(int taskId);
  Future<void> deleteTask(int taskId);
  Future<List<Task>> getTodayTasks();
  Future<List<Task>> searchTasks(String query);
  Future<Task> postponeTask(int taskId);
  Future<List<Task>> getTasksForMonth(int year, int month);
  Future<List<Task>> getCompletedTasks();
  Future<List<Task>> getAllTasks();

  // ===== 子任务 =====
  Future<List<Subtask>> getSubtasks(int taskId);
  Future<Subtask> createSubtask(int taskId, String title);
  Future<Subtask> toggleSubtask(int taskId, int subtaskId);
  Future<void> deleteSubtask(int taskId, int subtaskId);
  Future<Map<String, int>> getSubtaskProgress(int taskId);

  // ===== 标签 =====
  Future<List<Tag>> getTags();
  Future<Tag> createTag({required String name, required String color});
  Future<Tag> updateTag({required int id, String? name, String? color});
  Future<void> deleteTag(int tagId);
  Future<List<Task>> getTasksByTag(int tagId);

  // ===== 习惯 =====
  Future<List<Map<String, dynamic>>> getHabits();
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
  });
  Future<void> updateHabit(int habitId, Map<String, dynamic> data);
  Future<Map<String, dynamic>> checkInHabit(
    int habitId, {
    String note = '',
    String? date,
    int? durationMin,
    String? period,
  });
  Future<Map<String, dynamic>> uncheckInHabit(int habitId);
  Future<Map<String, dynamic>> getHabitLogs(int habitId, {String? month});
  Future<void> deleteHabit(int habitId);

  // ===== 观察标签（历史命名仍为 SystemTag） =====
  Future<List<Map<String, dynamic>>> getSystemTags();
  Future<Map<String, dynamic>> createSystemTag({
    required String name,
    required String icon,
    required String color,
  });
  Future<Map<String, dynamic>> updateSystemTag(
    int id, {
    String? icon,
    String? color,
  });
  Future<void> deleteSystemTag(int id);

  // ===== 收集箱 =====
  Future<Map<String, dynamic>> getInbox();
  Future<Task> quickAddToInbox(String title, {int? systemTagId});
  Future<Task> moveInboxTask(int taskId, int listId);
  Future<int> getInboxCount();
}
