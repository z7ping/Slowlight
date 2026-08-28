import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/subtask.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/repositories/task_repository.dart';
import 'package:slowlight/services/data_source.dart';

/// TaskRepository 只关心任务/子任务能力；其余 ApiDataSource 成员由
/// noSuchMethod forwarding 提供测试桩，避免测试复制整份数据源接口。
class MockTaskDataSource implements ApiDataSource {
  final List<Task> _tasks = [];
  final List<Subtask> _subtasks = [];
  int _nextId = 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<Task>> getTasks(int listId) async =>
      _tasks.where((task) => task.listId == listId).toList();

  @override
  Future<List<Task>> getAllTasks() async => List.of(_tasks);

  @override
  Future<List<Task>> getTodayTasks() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _tasks.where((task) {
      if (task.isCompleted) return false;
      final due = task.dueDate;
      if (due == null) return true;
      final date = DateTime(due.year, due.month, due.day);
      return !date.isAfter(today);
    }).toList();
  }

  @override
  Future<List<Task>> getCompletedTasks() async =>
      _tasks.where((task) => task.isCompleted).toList();

  @override
  Future<List<Task>> getTasksForMonth(int year, int month) async => _tasks
      .where((task) =>
          task.dueDate != null &&
          task.dueDate!.year == year &&
          task.dueDate!.month == month)
      .toList();

  @override
  Future<List<Task>> searchTasks(String query) async => _tasks
      .where((task) => task.title.toLowerCase().contains(query.toLowerCase()))
      .toList();

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
  }) async {
    final task = Task(
      id: _nextId++,
      listId: listId,
      title: title,
      description: description,
      priority: priority,
      dueDate: dueDate,
      dueTime: dueTime,
      isCompleted: false,
      repeatType: repeatType,
      repeatInterval: repeatInterval,
      repeatDays: repeatDays,
      reminderAt: reminderAt,
      reminderAdvanceMinutes: reminderAdvanceMinutes,
      createdAt: DateTime.now(),
      systemTagId: systemTagId,
      taskType: taskType,
      moodBefore: moodBefore,
      moodAfter: moodAfter,
      isMilestone: isMilestone,
      relatedQuestId: relatedQuestId,
      obsidianLink: obsidianLink,
      outputLevel: outputLevel,
    );
    _tasks.add(task);
    return task;
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
  }) async {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index < 0) throw StateError('Task not found');
    final previous = _tasks[index];
    final updated = Task(
      id: taskId,
      listId: listId,
      title: title,
      description: description,
      priority: priority,
      dueDate: dueDate,
      dueTime: dueTime,
      isCompleted: previous.isCompleted,
      completedAt: previous.completedAt,
      repeatType: repeatType,
      repeatInterval: repeatInterval,
      repeatDays: repeatDays,
      reminderAt: reminderAt,
      reminderAdvanceMinutes: reminderAdvanceMinutes,
      createdAt: previous.createdAt,
      systemTagId: systemTagId,
      taskType: taskType,
      moodBefore: moodBefore,
      moodAfter: moodAfter,
      isMilestone: isMilestone,
      relatedQuestId: relatedQuestId,
      obsidianLink: obsidianLink,
      outputLevel: outputLevel,
    );
    _tasks[index] = updated;
    return updated;
  }

  @override
  Future<Task> completeTask(int taskId) async {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index < 0) throw StateError('Task not found');
    final task = _tasks[index];
    final completed = Task(
      id: task.id,
      listId: task.listId,
      title: task.title,
      description: task.description,
      priority: task.priority,
      dueDate: task.dueDate,
      dueTime: task.dueTime,
      isCompleted: true,
      completedAt: DateTime.now(),
      repeatType: task.repeatType,
      repeatInterval: task.repeatInterval,
      repeatDays: task.repeatDays,
      reminderAt: task.reminderAt,
      reminderAdvanceMinutes: task.reminderAdvanceMinutes,
      createdAt: task.createdAt,
      systemTagId: task.systemTagId,
      taskType: task.taskType,
      moodBefore: task.moodBefore,
      moodAfter: task.moodAfter,
      isMilestone: task.isMilestone,
      relatedQuestId: task.relatedQuestId,
      obsidianLink: task.obsidianLink,
      outputLevel: task.outputLevel,
    );
    _tasks[index] = completed;
    return completed;
  }

  @override
  Future<Task> postponeTask(int taskId) async {
    final task = _tasks.firstWhere((item) => item.id == taskId);
    final now = DateTime.now();
    return updateTask(
      taskId: task.id,
      listId: task.listId,
      title: task.title,
      description: task.description,
      priority: task.priority,
      dueDate: DateTime(now.year, now.month, now.day),
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
  Future<void> deleteTask(int taskId) async {
    _tasks.removeWhere((task) => task.id == taskId);
  }

  @override
  Future<List<Subtask>> getSubtasks(int taskId) async =>
      _subtasks.where((item) => item.taskId == taskId).toList();

  @override
  Future<Subtask> createSubtask(int taskId, String title) async {
    final subtask = Subtask(
      id: _nextId++,
      taskId: taskId,
      title: title,
      createdAt: DateTime.now(),
    );
    _subtasks.add(subtask);
    return subtask;
  }

  @override
  Future<Subtask> toggleSubtask(int taskId, int subtaskId) async {
    final index = _subtasks.indexWhere(
      (item) => item.id == subtaskId && item.taskId == taskId,
    );
    if (index < 0) throw StateError('Subtask not found');
    final item = _subtasks[index];
    final toggled = Subtask(
      id: item.id,
      taskId: item.taskId,
      title: item.title,
      isCompleted: !item.isCompleted,
      sortOrder: item.sortOrder,
      createdAt: item.createdAt,
    );
    _subtasks[index] = toggled;
    return toggled;
  }

  @override
  Future<void> deleteSubtask(int taskId, int subtaskId) async {
    _subtasks.removeWhere(
      (item) => item.id == subtaskId && item.taskId == taskId,
    );
  }

  @override
  Future<Map<String, int>> getSubtaskProgress(int taskId) async {
    final items = _subtasks.where((item) => item.taskId == taskId).toList();
    return {
      'total': items.length,
      'completed': items.where((item) => item.isCompleted).length,
    };
  }
}

void main() {
  group('TaskRepository', () {
    late TaskRepository repository;
    late MockTaskDataSource dataSource;

    setUp(() {
      dataSource = MockTaskDataSource();
      repository = TaskRepository(dataSource: dataSource);
    });

    test('creates and reads tasks through data source', () async {
      await repository.create(listId: 1, title: 'A');
      await repository.create(listId: 1, title: 'B');
      await repository.create(listId: 2, title: 'C');

      expect((await repository.getTasksByListId(1)).length, 2);
      expect((await repository.getAll()).length, 3);
    });

    test('passes long-term task semantics through create and update', () async {
      final created = await repository.create(
        listId: 1,
        title: 'Milestone',
        taskType: 'main',
        moodBefore: 2,
        moodAfter: 4,
        isMilestone: true,
        relatedQuestId: 9,
        obsidianLink: 'obsidian://task',
        outputLevel: 'A',
      );

      expect(created.taskType, 'main');
      expect(created.isMilestone, isTrue);
      expect(created.outputLevel, 'A');

      final updated = await repository.updateTask(
        taskId: created.id,
        listId: 1,
        title: 'Milestone updated',
        taskType: 'branch',
        moodBefore: 3,
        moodAfter: 5,
        isMilestone: true,
        relatedQuestId: 10,
        obsidianLink: 'obsidian://updated',
        outputLevel: 'S',
      );

      expect(updated.taskType, 'branch');
      expect(updated.moodBefore, 3);
      expect(updated.moodAfter, 5);
      expect(updated.relatedQuestId, 10);
      expect(updated.obsidianLink, 'obsidian://updated');
      expect(updated.outputLevel, 'S');
    });

    test('complete and completed query work', () async {
      final task = await repository.create(listId: 1, title: 'Done');
      final completed = await repository.completeTask(task.id);

      expect(completed.isCompleted, isTrue);
      expect(completed.completedAt, isNotNull);
      expect((await repository.getCompletedTasks()).single.id, task.id);
    });

    test('search, month query and postpone work', () async {
      final due = await repository.create(
        listId: 1,
        title: 'Read book',
        dueDate: DateTime(2026, 6, 15),
      );

      expect((await repository.search('book')).single.id, due.id);
      expect((await repository.getTasksForMonth(2026, 6)).single.id, due.id);
      expect((await repository.postponeTask(due.id)).dueDate, isNotNull);
    });

    test('delete removes task', () async {
      final task = await repository.create(listId: 1, title: 'Delete');
      await repository.deleteTask(task.id);
      expect(await repository.getAll(), isEmpty);
    });

    test('subtask create, toggle, progress and delete work', () async {
      final task = await repository.create(listId: 1, title: 'Parent');
      final subtask = await repository.createSubtask(task.id, 'Child');

      expect((await repository.getSubtasks(task.id)).single.id, subtask.id);
      expect((await repository.toggleSubtask(task.id, subtask.id)).isCompleted, isTrue);
      expect(await repository.getSubtaskProgress(task.id), {
        'total': 1,
        'completed': 1,
      });

      await repository.deleteSubtask(task.id, subtask.id);
      expect(await repository.getSubtasks(task.id), isEmpty);
    });
  });
}
