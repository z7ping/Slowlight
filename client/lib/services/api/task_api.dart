import 'dart:convert';
import 'package:http/http.dart' as http;
import '../http_util.dart';
import '../../models/task.dart';
import '../../repositories/local_task_repository.dart';
import '../api_service.dart';
import '../data_mode_manager.dart';
import '../local_api_service.dart';

/// 任务相关 API。
///
/// Data Mode 只决定数据来源：Local 直接落 SQLite，Cloud 调 Slowlight Server。
class TaskApi {
  static final _localApi = LocalApiService();
  static final _localTaskRepo = LocalTaskRepository();

  /// 获取单个任务
  static Future<Task> getTask(int taskId) async {
    if (DataModeManager().isLocal) {
      return _localApi.getTask(taskId);
    }
    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('${ApiService.baseUrl}/tasks/$taskId'),
      headers: headers,
    ).timeout(ApiService.getTimeout);
    if (response.statusCode == 200) {
      return Task.fromJson(json.decode(response.body));
    }
    throw Exception('获取任务失败');
  }

  /// 获取任务列表
  static Future<List<Task>> getTasks(int listId) async {
    if (DataModeManager().isLocal) {
      return _localApi.getTasks(listId);
    }
    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('${ApiService.baseUrl}/lists/$listId/tasks'),
      headers: headers,
    ).timeout(ApiService.getTimeout);
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Task.fromJson(json)).toList();
    }
    throw Exception('获取任务失败');
  }

  /// 创建任务
  static Future<Task> createTask({
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
    if (DataModeManager().isLocal) {
      return _localTaskRepo.create(
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
    }

    final headers = await ApiService.authHeaders();
    final body = <String, dynamic>{
      'list_id': listId,
      'title': title,
      'description': description,
      'priority': priority,
      'due_date': dueDate != null
          ? '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}'
          : null,
      'due_time': dueTime,
      'repeat_type': repeatType,
      'repeat_interval': repeatInterval,
      'repeat_days': repeatDays,
      'reminder_at': reminderAt?.toUtc().toIso8601String(),
      'reminder_advance_minutes': reminderAdvanceMinutes,
      'task_type': taskType,
      'mood_before': moodBefore,
      'mood_after': moodAfter,
      'is_milestone': isMilestone,
      'related_quest_id': relatedQuestId,
      'obsidian_link': obsidianLink,
      'output_level': outputLevel,
    };
    if (tagIds != null && tagIds.isNotEmpty) body['tag_ids'] = tagIds;
    if (systemTagId != null) body['system_tag_id'] = systemTagId;

    final response = await HttpUtil.post(
      Uri.parse('${ApiService.baseUrl}/tasks'),
      headers: headers,
      body: json.encode(body),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode == 201) {
      return Task.fromJson(json.decode(response.body));
    }
    throw Exception('创建任务失败: ${response.statusCode} ${response.body}');
  }

  /// 更新任务
  static Future<Task> updateTask({
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
    if (DataModeManager().isLocal) {
      return _localTaskRepo.update(
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
    }

    final headers = await ApiService.authHeaders();
    final body = <String, dynamic>{
      'list_id': listId,
      'title': title,
      'description': description,
      'priority': priority,
      'due_date': dueDate != null
          ? '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}'
          : null,
      'due_time': dueTime,
      'repeat_type': repeatType,
      'repeat_interval': repeatInterval,
      'repeat_days': repeatDays,
      'reminder_at': reminderAt?.toUtc().toIso8601String(),
      'reminder_advance_minutes': reminderAdvanceMinutes,
      'task_type': taskType,
      'mood_before': moodBefore,
      'mood_after': moodAfter,
      'is_milestone': isMilestone,
      'related_quest_id': relatedQuestId,
      'obsidian_link': obsidianLink,
      'output_level': outputLevel,
    };
    if (tagIds != null) body['tag_ids'] = tagIds;
    if (systemTagId != null) body['system_tag_id'] = systemTagId;

    final response = await HttpUtil.put(
      Uri.parse('${ApiService.baseUrl}/tasks/$taskId'),
      headers: headers,
      body: json.encode(body),
    ).timeout(ApiService.postTimeout);
    if (response.statusCode == 200) {
      return Task.fromJson(json.decode(response.body));
    }
    throw Exception('更新任务失败');
  }

  /// 删除任务
  static Future<void> deleteTask(int taskId) async {
    if (DataModeManager().isLocal) {
      return _localApi.deleteTask(taskId);
    }
    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.delete(
      Uri.parse('${ApiService.baseUrl}/tasks/$taskId'),
      headers: headers,
    ).timeout(ApiService.getTimeout);
    if (response.statusCode != 200) throw Exception('删除失败');
  }

  /// 获取今日任务
  static Future<List<Task>> getTodayTasks() async {
    if (DataModeManager().isLocal) return _localApi.getTodayTasks();
    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('${ApiService.baseUrl}/tasks/today'),
      headers: headers,
    ).timeout(ApiService.getTimeout);
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Task.fromJson(json)).toList();
    }
    throw Exception('获取今日任务失败');
  }

  /// 完成/取消完成任务。云端端点当前是 toggle；本地只用于完成。
  static Future<Task> completeTask(int taskId) async {
    if (DataModeManager().isLocal) return _localApi.completeTask(taskId);
    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.patch(
      Uri.parse('${ApiService.baseUrl}/tasks/$taskId/complete'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return Task.fromJson(json.decode(response.body));
    }
    throw Exception('完成任务失败');
  }

  /// 顺延任务
  static Future<Task> postponeTask(int taskId) async {
    if (DataModeManager().isLocal) return _localApi.postponeTask(taskId);
    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.patch(
      Uri.parse('${ApiService.baseUrl}/tasks/$taskId/postpone'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return Task.fromJson(json.decode(response.body));
    }
    throw Exception('顺延任务失败');
  }

  /// 搜索任务
  static Future<List<Task>> searchTasks(String query) async {
    if (DataModeManager().isLocal) return _localApi.searchTasks(query);
    if (query.trim().isEmpty) return [];
    final headers = await ApiService.authHeaders();
    final uri = Uri.parse('${ApiService.baseUrl}/tasks/search')
        .replace(queryParameters: {'q': query});
    final response =
        await HttpUtil.get(uri, headers: headers).timeout(ApiService.getTimeout);
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Task.fromJson(json)).toList();
    }
    throw Exception('搜索失败');
  }

  /// 获取某月任务
  static Future<List<Task>> getTasksForMonth(int year, int month) async {
    if (DataModeManager().isLocal) {
      return _localApi.getTasksForMonth(year, month);
    }
    final headers = await ApiService.authHeaders();
    final listsResponse = await HttpUtil.get(
      Uri.parse('${ApiService.baseUrl}/lists'),
      headers: headers,
    ).timeout(ApiService.getTimeout);
    if (listsResponse.statusCode != 200) throw Exception('获取清单失败');
    final List<dynamic> lists = json.decode(listsResponse.body);
    final allTasks = <Task>[];
    for (final list in lists) {
      final tasksResponse = await HttpUtil.get(
        Uri.parse('${ApiService.baseUrl}/lists/${list['id']}/tasks'),
        headers: headers,
      ).timeout(ApiService.getTimeout);
      if (tasksResponse.statusCode == 200) {
        final List<dynamic> data = json.decode(tasksResponse.body);
        allTasks.addAll(data.map((j) => Task.fromJson(j)));
      }
    }
    return allTasks.where((t) {
      final d = t.dueDate;
      if (d == null) return false;
      final local = d.toLocal();
      return local.year == year && local.month == month;
    }).toList();
  }

  /// 获取已完成任务
  static Future<List<Task>> getCompletedTasks() async {
    if (DataModeManager().isLocal) return _localApi.getCompletedTasks();
    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('${ApiService.baseUrl}/tasks/completed'),
      headers: headers,
    ).timeout(ApiService.getTimeout);
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Task.fromJson(json)).toList();
    }
    throw Exception('获取已完成任务失败');
  }

  /// 获取所有任务
  static Future<List<Task>> getAllTasks() async {
    if (DataModeManager().isLocal) return _localApi.getAllTasks();
    final headers = await ApiService.authHeaders();
    final listsResponse = await HttpUtil.get(
      Uri.parse('${ApiService.baseUrl}/lists'),
      headers: headers,
    ).timeout(ApiService.getTimeout);
    if (listsResponse.statusCode != 200) throw Exception('获取清单失败');
    final List<dynamic> lists = json.decode(listsResponse.body);
    final allTasks = <Task>[];
    for (final list in lists) {
      try {
        final tasksResponse = await HttpUtil.get(
          Uri.parse('${ApiService.baseUrl}/lists/${list['id']}/tasks'),
          headers: headers,
        ).timeout(ApiService.getTimeout);
        if (tasksResponse.statusCode == 200) {
          final List<dynamic> data = json.decode(tasksResponse.body);
          allTasks.addAll(data.map((j) => Task.fromJson(j)));
        }
      } catch (_) {
        // 单个清单失败不阻塞其他清单。
      }
    }
    return allTasks;
  }
}
