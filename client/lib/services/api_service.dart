import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'http_util.dart';
import '../models/subtask.dart';
import '../models/todo_list.dart';
import '../models/task.dart';
import '../models/tag.dart';
import 'auth_service.dart';
import 'data_mode_manager.dart';
import 'local_api_service.dart';
import 'review_local_service.dart';
import 'api/task_api.dart';

final _localApi = LocalApiService();

class ApiService {
  static const Duration _getTimeout = Duration(seconds: 8);
  static const Duration _postTimeout = Duration(seconds: 15);
  static const String baseUrl = String.fromEnvironment("SERVER_URL",
      defaultValue: "http://localhost:8080/api");

  // Public accessors for sub-API modules (e.g. TaskApi)
  static Duration get getTimeout => _getTimeout;
  static Duration get postTimeout => _postTimeout;
  static Future<Map<String, String>> Function() get authHeaders => _authHeaders;

  /// 获取认证 headers
  static Future<Map<String, String>> _authHeaders() async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = await AuthService.getToken();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// 通用 POST 请求（用于登录/注册）
  static Future<Map<String, dynamic>> post(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    ).timeout(_postTimeout);
    final data = json.decode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['error'] ?? '请求失败');
  }

  /// 迁移预览只进行云端比对，不会写入任何记录。
  static Future<Map<String, dynamic>> previewMigration(
    Map<String, dynamic> snapshot,
  ) async {
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/migration/preview'),
      headers: await _authHeaders(),
      body: json.encode(snapshot),
    ).timeout(_postTimeout);
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error'] ?? '迁移预览失败');
  }

  static Future<Map<String, dynamic>> executeMigration(
    Map<String, dynamic> snapshot,
  ) async {
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/migration/execute'),
      headers: await _authHeaders(),
      body: json.encode(snapshot),
    ).timeout(_postTimeout);
    final data = json.decode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200) return data;
    throw Exception(data['error'] ?? '迁移执行失败');
  }

  static Future<Map<String, dynamic>?> getLatestMigrationReport() async {
    final response = await HttpUtil.get(
            Uri.parse('$baseUrl/migration/reports/latest'),
            headers: await _authHeaders())
        .timeout(_getTimeout);
    if (response.statusCode == 404) return null;
    if (response.statusCode == 200)
      return json.decode(response.body) as Map<String, dynamic>;
    throw Exception('获取迁移报告失败');
  }

  static Future<List<Map<String, dynamic>>> getMigrationReports() async {
    final response = await HttpUtil.get(Uri.parse('$baseUrl/migration/reports'),
            headers: await _authHeaders())
        .timeout(_getTimeout);
    if (response.statusCode != 200) throw Exception('获取迁移历史失败');
    final body = json.decode(response.body) as Map<String, dynamic>;
    return (body['reports'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  // ==================== CalDAV 接口 ====================

  /// 获取 CalDAV 配置
  static Future<Map<String, dynamic>> getCalDAVConfig() async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/caldav/config'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('获取 CalDAV 配置失败');
  }

  /// 保存 CalDAV 配置
  static Future<Map<String, dynamic>> saveCalDAVConfig({
    required String baseUrl,
    required String username,
    required String password,
    List<String> paths = const [],
  }) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/caldav/config'),
      headers: headers,
      body: json.encode({
        'base_url': baseUrl,
        'username': username,
        'password': password,
        'paths': paths,
      }),
    ).timeout(_postTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('保存 CalDAV 配置失败');
  }

  /// 测试 CalDAV 连接
  static Future<Map<String, dynamic>> testCalDAVConnection({
    required String baseUrl,
    required String username,
    required String password,
    List<String> paths = const [],
  }) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/caldav/test'),
      headers: headers,
      body: json.encode({
        'base_url': baseUrl,
        'username': username,
        'password': password,
        'paths': paths,
      }),
    ).timeout(_postTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('测试 CalDAV 连接失败');
  }

  /// 获取 CalDAV 同步状态
  static Future<Map<String, dynamic>> getCalDAVStatus() async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/caldav/status'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('获取 CalDAV 状态失败');
  }

  /// 手动触发 CalDAV 同步
  static Future<Map<String, dynamic>> syncCalDAV() async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/caldav/sync'),
      headers: headers,
    ).timeout(_postTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('CalDAV 同步失败');
  }

  // ==================== 项目管理 ====================

  // 获取所有清单
  static Future<List<TodoList>> getLists() async {
    if (DataModeManager().isOffline) return _localApi.getLists();
    final headers = await _authHeaders();
    final response =
        await HttpUtil.get(Uri.parse('$baseUrl/lists'), headers: headers)
            .timeout(_getTimeout);
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => TodoList.fromJson(json)).toList();
    }
    throw Exception('获取清单失败');
  }

  // 创建清单
  static Future<TodoList> createList({
    required String name,
    String icon = '📁',
    String color = '#1890ff',
    bool isInbox = false,
  }) async {
    if (DataModeManager().isOffline)
      return _localApi.createList(
          name: name, icon: icon, color: color, isInbox: isInbox);
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/lists'),
      headers: headers,
      body: json.encode({
        'name': name,
        'icon': icon,
        'color': color,
        'is_inbox': isInbox,
      }),
    ).timeout(_postTimeout);
    if (response.statusCode == 201) {
      return TodoList.fromJson(json.decode(response.body));
    }
    throw Exception('创建清单失败');
  }

  // 更新清单
  static Future<TodoList> updateList({
    required int id,
    String? name,
    String? icon,
    String? color,
  }) async {
    if (DataModeManager().isOffline)
      return _localApi.updateList(id: id, name: name, icon: icon, color: color);
    final headers = await _authHeaders();
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (icon != null) body['icon'] = icon;
    if (color != null) body['color'] = color;
    final response = await HttpUtil.put(
      Uri.parse('$baseUrl/lists/$id'),
      headers: headers,
      body: json.encode(body),
    ).timeout(_postTimeout);
    if (response.statusCode == 200) {
      return TodoList.fromJson(json.decode(response.body));
    }
    throw Exception('更新清单失败');
  }

  // 删除清单
  static Future<void> deleteList(int id) async {
    if (DataModeManager().isOffline) return _localApi.deleteList(id);
    final headers = await _authHeaders();
    final response = await HttpUtil.delete(
      Uri.parse('$baseUrl/lists/$id'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode != 200) {
      throw Exception('删除清单失败');
    }
  }

  // 获取单个任务
  static Future<Task> getTask(int taskId) => TaskApi.getTask(taskId);

  // 获取清单下的任务
  static Future<List<Task>> getTasks(int listId) => TaskApi.getTasks(listId);

  // 创建任务
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
  }) =>
      TaskApi.createTask(
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
      );

  // 更新任务
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
  }) =>
      TaskApi.updateTask(
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
      );

  // 完成任务
  static Future<Task> completeTask(int taskId) => TaskApi.completeTask(taskId);

  // 删除任务
  static Future<void> deleteTask(int taskId) => TaskApi.deleteTask(taskId);

  // 获取今日任务
  static Future<List<Task>> getTodayTasks() => TaskApi.getTodayTasks();

  // 全局搜索任务
  static Future<List<Task>> searchTasks(String query) =>
      TaskApi.searchTasks(query);

  /// 顺延任务到今天
  static Future<Task> postponeTask(int taskId) => TaskApi.postponeTask(taskId);

  // 获取指定月份所有有 due_date 的任务（前端筛选）
  static Future<List<Task>> getTasksForMonth(int year, int month) =>
      TaskApi.getTasksForMonth(year, month);

  // 获取已完成任务
  static Future<List<Task>> getCompletedTasks() => TaskApi.getCompletedTasks();

  // 获取所有清单的所有任务（用于统计）
  static Future<List<Task>> getAllTasks() => TaskApi.getAllTasks();

  // ===== 习惯打卡 API =====

  // 获取习惯列表
  static Future<List<Map<String, dynamic>>> getHabits() async {
    if (DataModeManager().isOffline) return _localApi.getHabits();
    final headers = await _authHeaders();
    final response =
        await HttpUtil.get(Uri.parse('$baseUrl/habits'), headers: headers)
            .timeout(_getTimeout);
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>().toList();
    }
    throw Exception('获取习惯列表失败');
  }

  // 创建习惯
  static Future<Map<String, dynamic>> createHabit({
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
    if (DataModeManager().isOffline)
      return _localApi.createHabit(
        name: name,
        icon: icon,
        color: color,
        frequency: frequency,
        targetDays: targetDays,
        systemTagId: systemTagId,
        preferredPeriod: preferredPeriod,
        durationMin: durationMin,
        generateTask: generateTask,
        specificTime: specificTime,
        showCheckinDialog: showCheckinDialog,
        reminderAt: reminderAt,
      );
    final headers = await _authHeaders();
    final body = <String, dynamic>{
      'name': name,
      'icon': icon,
      'color': color,
      'frequency': frequency,
      'target_days': targetDays,
      'preferred_period': preferredPeriod,
      'duration_min': durationMin,
      'generate_task': generateTask,
      'show_checkin_dialog': showCheckinDialog,
      'specific_time': specificTime,
      'reminder_at': reminderAt ?? {},
    };
    if (systemTagId != null) body['system_tag_id'] = systemTagId;
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/habits'),
      headers: headers,
      body: json.encode(body),
    ).timeout(_postTimeout);
    if (response.statusCode == 201) {
      return json.decode(response.body);
    }
    throw Exception('创建习惯失败');
  }

  // 获取系统标签
  static Future<List<Map<String, dynamic>>> getSystemTags() async {
    if (DataModeManager().isOffline) return _localApi.getSystemTags();
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/system-tags'),
      headers: headers,
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('获取系统标签失败: ${response.statusCode}');
  }

  // 创建系统标签
  static Future<Map<String, dynamic>> createSystemTag({
    required String name,
    required String icon,
    required String color,
  }) async {
    if (DataModeManager().isOffline)
      return _localApi.createSystemTag(name: name, icon: icon, color: color);
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/system-tags'),
      headers: headers,
      body: json.encode({'name': name, 'icon': icon, 'color': color}),
    ).timeout(_postTimeout);
    if (response.statusCode == 201) {
      return json.decode(response.body);
    }
    throw Exception('创建系统标签失败');
  }

  // 删除系统标签
  static Future<void> deleteSystemTag(int id) async {
    if (DataModeManager().isOffline) return _localApi.deleteSystemTag(id);
    final headers = await _authHeaders();
    final response = await HttpUtil.delete(
      Uri.parse('$baseUrl/system-tags/$id'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode != 200) {
      throw Exception('删除系统标签失败');
    }
  }

  // 打卡（可指定日期补卡）
  static Future<Map<String, dynamic>> checkInHabit(int habitId,
      {String note = '',
      String? date,
      int? durationMin,
      String? period}) async {
    if (DataModeManager().isOffline)
      return _localApi.checkInHabit(habitId,
          note: note, date: date, durationMin: durationMin, period: period);
    final headers = await _authHeaders();
    final body = <String, dynamic>{
      'note': note,
      'duration_min': durationMin ?? 0,
      'period': period ?? ''
    };
    if (date != null) body['date'] = date; // YYYY-MM-DD
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/habits/$habitId/checkin'),
      headers: headers,
      body: json.encode(body),
    ).timeout(_postTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    // 返回服务器的具体错误信息
    try {
      final err = json.decode(response.body);
      throw Exception(err['error'] ?? '打卡失败(${response.statusCode})');
    } catch (e) {
      throw Exception('打卡失败(${response.statusCode})');
    }
  }

  // 取消打卡
  static Future<Map<String, dynamic>> uncheckInHabit(int habitId) async {
    if (DataModeManager().isOffline) return _localApi.uncheckInHabit(habitId);
    final headers = await _authHeaders();
    final response = await HttpUtil.delete(
      Uri.parse('$baseUrl/habits/$habitId/checkin'),
      headers: headers,
    ).timeout(_postTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    try {
      final err = json.decode(response.body);
      throw Exception(err['error'] ?? '取消打卡失败(${response.statusCode})');
    } catch (e) {
      if (e is Exception && e.toString().contains('取消打卡失败')) rethrow;
      throw Exception('取消打卡失败(${response.statusCode})');
    }
  }

  // 获取打卡记录
  static Future<Map<String, dynamic>> getHabitLogs(int habitId,
      {String? month}) async {
    if (DataModeManager().isOffline)
      return _localApi.getHabitLogs(habitId, month: month);
    final headers = await _authHeaders();
    final url = month != null
        ? '$baseUrl/habits/$habitId/logs?month=$month'
        : '$baseUrl/habits/$habitId/logs';
    final response = await HttpUtil.get(Uri.parse(url), headers: headers)
        .timeout(_getTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('获取打卡记录失败');
  }

  // 更新已有打卡记录
  static Future<Map<String, dynamic>> updateHabitLog(
    int habitId,
    int logId,
    Map<String, dynamic> data,
  ) async {
    if (DataModeManager().isOffline) {
      return _localApi.updateHabitLog(habitId, logId, data);
    }
    final headers = await _authHeaders();
    final response = await HttpUtil.put(
      Uri.parse('$baseUrl/habits/$habitId/logs/$logId'),
      headers: headers,
      body: jsonEncode(data),
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    try {
      final err = json.decode(response.body);
      throw Exception(err['error'] ?? '更新打卡记录失败');
    } catch (e) {
      if (e is Exception && e.toString().contains('更新打卡记录失败')) rethrow;
      throw Exception('更新打卡记录失败');
    }
  }

  // 删除习惯
  static Future<void> deleteHabit(int habitId) async {
    if (DataModeManager().isOffline) return _localApi.deleteHabit(habitId);
    final headers = await _authHeaders();
    final response = await HttpUtil.delete(
      Uri.parse('$baseUrl/habits/$habitId'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode != 200) {
      throw Exception('删除失败');
    }
  }

  // 更新习惯
  static Future<void> updateHabit(
      int habitId, Map<String, dynamic> data) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.put(
      Uri.parse('$baseUrl/habits/$habitId'),
      headers: headers,
      body: jsonEncode(data),
    ).timeout(_postTimeout);
    if (response.statusCode != 200) {
      throw Exception('更新习惯失败');
    }
  }

  // 获取习惯连续打卡天数
  static Future<Map<String, dynamic>> getHabitStreak(int habitId) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/habits/$habitId/streak'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('获取连续打卡失败');
  }

  // ===== 子任务 API =====

  // 获取任务的子任务列表
  static Future<List<Subtask>> getSubtasks(int taskId) async {
    if (DataModeManager().isOffline) return _localApi.getSubtasks(taskId);
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/tasks/$taskId/subtasks'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Subtask.fromJson(json)).toList();
    }
    throw Exception('获取子任务失败');
  }

  // 创建子任务
  static Future<Subtask> createSubtask(int taskId, String title) async {
    if (DataModeManager().isOffline)
      return _localApi.createSubtask(taskId, title);
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/tasks/$taskId/subtasks'),
      headers: headers,
      body: json.encode({'title': title}),
    ).timeout(_postTimeout);
    if (response.statusCode == 201) {
      return Subtask.fromJson(json.decode(response.body));
    }
    throw Exception('创建子任务失败');
  }

  // 更新子任务
  static Future<Subtask> updateSubtask(
      int taskId, int subtaskId, Map<String, dynamic> data) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.put(
      Uri.parse('$baseUrl/tasks/$taskId/subtasks/$subtaskId'),
      headers: headers,
      body: json.encode(data),
    ).timeout(_postTimeout);
    if (response.statusCode == 200) {
      return Subtask.fromJson(json.decode(response.body));
    }
    throw Exception('更新子任务失败');
  }

  // 切换子任务完成状态
  static Future<Subtask> toggleSubtask(int taskId, int subtaskId) async {
    if (DataModeManager().isOffline)
      return _localApi.toggleSubtask(taskId, subtaskId);
    final headers = await _authHeaders();
    final response = await HttpUtil.patch(
      Uri.parse('$baseUrl/tasks/$taskId/subtasks/$subtaskId/toggle'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return Subtask.fromJson(json.decode(response.body));
    }
    throw Exception('切换子任务状态失败');
  }

  // 删除子任务
  static Future<void> deleteSubtask(int taskId, int subtaskId) async {
    if (DataModeManager().isOffline)
      return _localApi.deleteSubtask(taskId, subtaskId);
    final headers = await _authHeaders();
    final response = await HttpUtil.delete(
      Uri.parse('$baseUrl/tasks/$taskId/subtasks/$subtaskId'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode != 200) {
      throw Exception('删除子任务失败');
    }
  }

  // 获取子任务进度
  static Future<Map<String, int>> getSubtaskProgress(int taskId) async {
    if (DataModeManager().isOffline)
      return _localApi.getSubtaskProgress(taskId);
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/tasks/$taskId/subtasks/progress'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return {'total': data['total'], 'completed': data['completed']};
    }
    throw Exception('获取子任务进度失败');
  }

  // ===== 飞书集成 API =====

  // ========== 外部平台集成（飞书/Notion/...） ==========

  // 获取支持的平台列表
  static Future<List<dynamic>> getIntegrationPlatforms() async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
            Uri.parse('$baseUrl/integration/platforms'),
            headers: headers)
        .timeout(_getTimeout);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['platforms'] ?? [];
    }
    throw Exception('获取平台列表失败');
  }

  // 获取集成配置
  static Future<Map<String, dynamic>> getIntegrationConfig(
      String platform) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
            Uri.parse('$baseUrl/integration/$platform/config'),
            headers: headers)
        .timeout(_getTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('获取配置失败');
  }

  // 保存集成配置（tableUrl 可选）
  static Future<Map<String, dynamic>> saveIntegrationConfig({
    required String platform,
    required String appId,
    required String appSecret,
    String? tableUrl,
  }) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{
      'app_id': appId,
      'app_secret': appSecret,
    };
    if (tableUrl != null && tableUrl.isNotEmpty) {
      body['table_url'] = tableUrl;
    }
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/integration/$platform/config'),
      headers: headers,
      body: json.encode(body),
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    final error = json.decode(response.body);
    throw Exception(error['error'] ?? '保存配置失败');
  }

  // 创建集成数据模板
  static Future<Map<String, dynamic>> createIntegrationTemplate(
      String platform) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/integration/$platform/create-template'),
      headers: headers,
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    final err = json.decode(response.body);
    throw Exception(err['error'] ?? '创建模板失败');
  }

  // 绑定已有表格
  static Future<Map<String, dynamic>> connectExistingIntegration(
      String platform, String tableUrl) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/integration/$platform/connect-existing'),
      headers: headers,
      body: json.encode({'table_url': tableUrl}),
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    final err = json.decode(response.body);
    throw Exception(err['error'] ?? '绑定失败');
  }

  // 一键同步所有
  static Future<Map<String, dynamic>> syncAllIntegration(
      String platform) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/integration/$platform/sync-all'),
      headers: headers,
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    final err = json.decode(response.body);
    throw Exception(err['error'] ?? '同步全部失败');
  }

  // 同步单个类型
  static Future<Map<String, dynamic>> syncIntegrationTasks(
      String platform) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/integration/$platform/sync-tasks'),
      headers: headers,
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('同步任务失败');
  }

  static Future<Map<String, dynamic>> syncIntegrationSessions(
      String platform) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/integration/$platform/sync-sessions'),
      headers: headers,
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('同步番茄钟失败');
  }

  static Future<Map<String, dynamic>> syncIntegrationReminders(
      String platform) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/integration/$platform/sync-reminders'),
      headers: headers,
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('同步休息提醒失败');
  }

  static Future<Map<String, dynamic>> syncIntegrationTags(
      String platform) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/integration/$platform/sync-tags'),
      headers: headers,
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('同步标签失败');
  }

  static Future<Map<String, dynamic>> importIntegration(String platform) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/integration/$platform/import'),
      headers: headers,
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('导入失败');
  }

  // 获取平台日历列表
  static Future<List<dynamic>> getIntegrationCalendars(String platform) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/integration/$platform/calendars'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['calendars'] ?? [];
    }
    throw Exception('获取日历列表失败');
  }

  // 同步任务到日历
  static Future<Map<String, dynamic>> syncToCalendar(
      String platform, String calendarId) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/integration/$platform/sync-calendar'),
      headers: headers,
      body: json.encode({'calendar_id': calendarId}),
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    final err = json.decode(response.body);
    throw Exception(err['error'] ?? '同步日历失败');
  }

  // ========== Webhook 管理 ==========

  static Future<List<dynamic>> getWebhooks() async {
    final headers = await _authHeaders();
    final response =
        await HttpUtil.get(Uri.parse('$baseUrl/webhooks'), headers: headers)
            .timeout(_getTimeout);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['webhooks'] ?? [];
    }
    throw Exception('获取 Webhook 列表失败');
  }

  static Future<Map<String, dynamic>> createWebhook({
    required String url,
    required String event,
    String name = '',
  }) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/webhooks'),
      headers: headers,
      body: json.encode({'url': url, 'event': event, 'name': name}),
    ).timeout(_postTimeout);
    if (response.statusCode == 201) return json.decode(response.body);
    final err = json.decode(response.body);
    throw Exception(err['error'] ?? '创建失败');
  }

  static Future<Map<String, dynamic>> updateWebhook(int id,
      {required String url, required String event, String name = ''}) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.put(
      Uri.parse('$baseUrl/webhooks/$id'),
      headers: headers,
      body: json.encode({'url': url, 'event': event, 'name': name}),
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    final err = json.decode(response.body);
    throw Exception(err['error'] ?? '更新失败');
  }

  static Future<void> deleteWebhook(int id) async {
    final headers = await _authHeaders();
    await HttpUtil.delete(Uri.parse('$baseUrl/webhooks/$id'), headers: headers)
        .timeout(_getTimeout);
  }

  static Future<Map<String, dynamic>> testWebhook(int id) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/webhooks/$id/test'),
      headers: headers,
    ).timeout(_postTimeout);
    return json.decode(response.body);
  }

  // ========== 旧飞书 API 兼容层（转发到新接口） ==========
  static const String _feishuPlatform = 'feishu';

  static Future<Map<String, dynamic>> getFeishuConfig() =>
      getIntegrationConfig(_feishuPlatform);

  static Future<Map<String, dynamic>> saveFeishuConfig({
    required String appId,
    required String appSecret,
    required String tableUrl,
  }) =>
      saveIntegrationConfig(
        platform: _feishuPlatform,
        appId: appId,
        appSecret: appSecret,
        tableUrl: tableUrl,
      );

  static Future<Map<String, dynamic>> syncToFeishu() =>
      syncIntegrationTasks(_feishuPlatform);

  static Future<Map<String, dynamic>> importFromFeishu() =>
      importIntegration(_feishuPlatform);

  static Future<Map<String, dynamic>> createFeishuTemplate() =>
      createIntegrationTemplate(_feishuPlatform);

  static Future<Map<String, dynamic>> connectExistingFeishu(String tableUrl) =>
      connectExistingIntegration(_feishuPlatform, tableUrl);

  static Future<Map<String, dynamic>> syncSessionsToFeishu() =>
      syncIntegrationSessions(_feishuPlatform);

  static Future<Map<String, dynamic>> syncRemindersToFeishu() =>
      syncIntegrationReminders(_feishuPlatform);

  static Future<Map<String, dynamic>> syncTagsToFeishu() =>
      syncIntegrationTags(_feishuPlatform);

  // ========== 番茄钟 / 工作会话 ==========

  static Future<Map<String, dynamic>> startSession(String sessionType,
      {int? taskId, String device = 'web'}) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{
      'session_type': sessionType,
      'device': device
    };
    if (taskId != null) body['task_id'] = taskId;
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/sessions/start'),
      headers: headers,
      body: json.encode(body),
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('开始会话失败');
  }

  static Future<Map<String, dynamic>> endSession({int? systemTagId}) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{};
    if (systemTagId != null) body['system_tag_id'] = systemTagId;
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/sessions/end'),
      headers: headers,
      body: body.isNotEmpty ? json.encode(body) : null,
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('结束会话失败');
  }

  static Future<Map<String, dynamic>> getActiveSession() async {
    if (DataModeManager().isOffline) return {'active': false, 'session': null};
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/sessions/active'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('获取活跃会话失败');
  }

  static Future<Map<String, dynamic>> getSessionStats(
      {String period = 'week'}) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/sessions/stats?period=$period'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('获取统计数据失败');
  }

  static Future<Map<String, dynamic>> getTodaySessionStats() async {
    if (DataModeManager().isOffline)
      return {
        'total_work_seconds': 0,
        'total_break_seconds': 0,
        'work_count': 0
      };
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/sessions/today'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('获取今日统计失败');
  }

  // ===== 休息提醒 API =====

  static Future<Map<String, dynamic>> getReminderConfig() async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/reminder/config'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('获取休息提醒配置失败');
  }

  static Future<void> saveReminderConfig(Map<String, dynamic> config) async {
    final headers = await _authHeaders();
    headers['Content-Type'] = 'application/json';
    await HttpUtil.put(
      Uri.parse('$baseUrl/reminder/config'),
      headers: headers,
      body: json.encode(config),
    ).timeout(_postTimeout);
  }

  static Future<Map<String, dynamic>> startWorkSession() async {
    final headers = await _authHeaders();
    headers['Content-Type'] = 'application/json';
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/reminder/start-work'),
      headers: headers,
      body: json.encode({'device': 'web'}),
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('开始工作会话失败');
  }

  static Future<Map<String, dynamic>> startRestSession() async {
    final headers = await _authHeaders();
    headers['Content-Type'] = 'application/json';
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/reminder/start-rest'),
      headers: headers,
      body: json.encode({}),
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('开始休息失败');
  }

  static Future<Map<String, dynamic>> endRestSession() async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/reminder/end-rest'),
      headers: headers,
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('结束休息失败');
  }

  static Future<Map<String, dynamic>> skipRestSession() async {
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/reminder/skip-rest'),
      headers: headers,
    ).timeout(_postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('跳过休息失败');
  }

  static Future<Map<String, dynamic>> getReminderTodayStats() async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/reminder/today'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    return {
      'total_work_seconds': 0,
      'total_break_seconds': 0,
      'work_count': 0,
      'skip_count': 0
    };
  }

  // ===== 标签 API =====

  // 获取所有标签
  static Future<List<Tag>> getTags() async {
    if (DataModeManager().isOffline) return _localApi.getTags();
    final headers = await _authHeaders();
    final response =
        await HttpUtil.get(Uri.parse('$baseUrl/tags'), headers: headers)
            .timeout(_getTimeout);
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Tag.fromJson(json)).toList();
    }
    throw Exception('获取标签失败');
  }

  // 创建标签
  static Future<Tag> createTag(
      {required String name, required String color}) async {
    if (DataModeManager().isOffline)
      return _localApi.createTag(name: name, color: color);
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/tags'),
      headers: headers,
      body: json.encode({'name': name, 'color': color}),
    ).timeout(_postTimeout);
    if (response.statusCode == 201) {
      return Tag.fromJson(json.decode(response.body));
    }
    throw Exception('创建标签失败');
  }

  // 更新标签
  static Future<Tag> updateTag(
      {required int id, String? name, String? color}) async {
    if (DataModeManager().isOffline)
      return _localApi.updateTag(id: id, name: name, color: color);
    final headers = await _authHeaders();
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (color != null) body['color'] = color;

    final response = await HttpUtil.put(
      Uri.parse('$baseUrl/tags/$id'),
      headers: headers,
      body: json.encode(body),
    ).timeout(_postTimeout);
    if (response.statusCode == 200) {
      return Tag.fromJson(json.decode(response.body));
    }
    throw Exception('更新标签失败');
  }

  // 删除标签
  static Future<void> deleteTag(int tagId) async {
    if (DataModeManager().isOffline) return _localApi.deleteTag(tagId);
    final headers = await _authHeaders();
    final response = await HttpUtil.delete(
      Uri.parse('$baseUrl/tags/$tagId'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode != 200) {
      throw Exception('删除标签失败');
    }
  }

  // 获取指定标签下的任务
  static Future<List<Task>> getTasksByTag(int tagId) async {
    if (DataModeManager().isOffline) return _localApi.getTasksByTag(tagId);
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/tags/$tagId/tasks'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Task.fromJson(json)).toList();
    }
    throw Exception('获取任务失败');
  }

  // ===== 统计接口 =====

  // 任务统计
  static Future<Map<String, dynamic>> getTaskStats() async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/tasks/stats'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('获取任务统计失败');
  }

  // 清单统计
  static Future<List<dynamic>> getListStats() async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/lists/stats'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('获取清单统计失败');
  }

  // 标签统计
  static Future<List<dynamic>> getTagStats() async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/tags/stats'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('获取标签统计失败');
  }

  // 休息提醒统计
  static Future<Map<String, dynamic>> getReminderStats(
      {String period = 'week'}) async {
    if (DataModeManager().isOffline) {
      // 本地模式：返回简化数据
      return {
        'total_work_seconds': 0,
        'total_break_seconds': 0,
        'work_count': 0,
        'rest_count': 0,
        'skipped_count': 0,
        'is_active': false
      };
    }
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/reminder/stats?period=$period'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('获取休息提醒统计失败');
  }

  // ── 收集箱 ──

  // 获取收集箱任务
  static Future<Map<String, dynamic>> getInbox() async {
    if (DataModeManager().isOffline) return _localApi.getInbox();
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/inbox'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('获取收集箱失败');
  }

  // 快速添加到收集箱
  static Future<Task> quickAddToInbox(String title, {int? systemTagId}) async {
    if (DataModeManager().isOffline)
      return _localApi.quickAddToInbox(title, systemTagId: systemTagId);
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/inbox'),
      headers: headers,
      body: json.encode({
        'title': title,
        if (systemTagId != null) 'system_tag_id': systemTagId,
      }),
    ).timeout(_postTimeout);
    if (response.statusCode == 201)
      return Task.fromJson(json.decode(response.body));
    throw Exception('快速添加失败');
  }

  // 移动收集箱任务到其他清单
  static Future<Task> moveInboxTask(int taskId, int listId) async {
    if (DataModeManager().isOffline)
      return _localApi.moveInboxTask(taskId, listId);
    final headers = await _authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('$baseUrl/inbox/$taskId/move'),
      headers: headers,
      body: json.encode({'list_id': listId}),
    ).timeout(_postTimeout);
    if (response.statusCode == 200)
      return Task.fromJson(json.decode(response.body));
    throw Exception('移动任务失败');
  }

  // 获取收集箱任务数量
  static Future<int> getInboxCount() async {
    if (DataModeManager().isOffline) return _localApi.getInboxCount();
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/inbox/count'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body)['count'] ?? 0;
    }
    return 0;
  }

  // ========== 今日回顾 ==========

  // 获取今日回顾
  static Future<Map<String, dynamic>> getTodayReview() async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/review/today'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('获取今日回顾失败');
  }

  // 获取每日趋势（折线图数据）

  // 获取指定天数的任务回顾
  static Future<Map<String, dynamic>> getTasksReview({int days = 7}) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/review/tasks?days=$days'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('获取任务回顾失败');
  }

  static Future<List<Map<String, dynamic>>> getDailyTrend(
      {int days = 7}) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/analytics/daily-trend?days=$days'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['days'] as List).cast<Map<String, dynamic>>();
    }
    throw Exception('获取每日趋势失败');
  }

  // 获取时间分配（按系统标签聚合）
  static Future<Map<String, dynamic>> getTimeDistribution() async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/analytics/time-distribution'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('获取时间分配失败');
  }

  // 获取每周回顾
  static Future<Map<String, dynamic>> getWeeklyReview() async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/analytics/weekly-review'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('获取每周回顾失败');
  }

  // ========== Output 统计 ==========

  // 获取 Output 统计
  static Future<Map<String, dynamic>> getOutputStats(
      {String period = 'all'}) async {
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/analytics/output?period=$period'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('获取 Output 统计失败');
  }

  // 更新系统标签
  static Future<Map<String, dynamic>> updateSystemTag(
    int id, {
    String? name,
    String? icon,
    String? color,
  }) async {
    if (DataModeManager().isOffline)
      return _localApi.updateSystemTag(id, icon: icon, color: color);
    final headers = await _authHeaders();
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (icon != null) body['icon'] = icon;
    if (color != null) body['color'] = color;
    final response = await HttpUtil.put(
      Uri.parse('$baseUrl/system-tags/$id'),
      headers: headers,
      body: json.encode(body),
    ).timeout(_postTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('更新系统标签失败');
  }

  // 获取四维度状态摘要
  static Future<Map<String, dynamic>> getDimensionSummary() async {
    if (DataModeManager().isOffline) {
      return ReviewLocalService().computeDimensionSummary();
    }
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/analytics/dimension-summary'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('获取维度摘要失败');
  }

  // 获取今日番茄钟会话
  static Future<Map<String, dynamic>> getTodaySessions() async {
    if (DataModeManager().isOffline) {
      // 本地模式：返回简化数据
      return {'count': 0, 'total_minutes': 0};
    }
    final headers = await _authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('$baseUrl/sessions/today'),
      headers: headers,
    ).timeout(_getTimeout);
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('获取今日会话失败');
  }
}
