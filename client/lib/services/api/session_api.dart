import 'dart:convert';

import '../../repositories/local_session_repository.dart';
import '../api_service.dart';
import '../data_mode_manager.dart';
import '../http_util.dart';

/// 番茄钟 / WorkSession 数据入口。
///
/// Data Mode 只决定数据来源：
/// - Local → SQLite
/// - Cloud → Slowlight Server
class SessionApi {
  static final LocalSessionRepository _local = LocalSessionRepository();

  static Future<Map<String, dynamic>> startSession(
    String sessionType, {
    int? taskId,
    String device = 'desktop',
  }) async {
    if (DataModeManager().isLocal) {
      return _local.startSession(
        sessionType,
        taskId: taskId,
        device: device,
      );
    }

    final headers = await ApiService.authHeaders();
    final body = <String, dynamic>{
      'session_type': sessionType,
      'device': device,
    };
    if (taskId != null) body['task_id'] = taskId;
    final response = await HttpUtil.post(
      Uri.parse('${ApiService.baseUrl}/sessions/start'),
      headers: headers,
      body: json.encode(body),
    ).timeout(ApiService.postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('开始会话失败');
  }

  static Future<Map<String, dynamic>> endSession({int? systemTagId}) async {
    if (DataModeManager().isLocal) {
      return _local.endSession(systemTagId: systemTagId);
    }

    final headers = await ApiService.authHeaders();
    final body = <String, dynamic>{};
    if (systemTagId != null) body['system_tag_id'] = systemTagId;
    final response = await HttpUtil.post(
      Uri.parse('${ApiService.baseUrl}/sessions/end'),
      headers: headers,
      body: body.isEmpty ? null : json.encode(body),
    ).timeout(ApiService.postTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('结束会话失败');
  }

  static Future<Map<String, dynamic>> getActiveSession() async {
    if (DataModeManager().isLocal) return _local.getActiveSession();

    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('${ApiService.baseUrl}/sessions/active'),
      headers: headers,
    ).timeout(ApiService.getTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('获取活跃会话失败');
  }

  static Future<Map<String, dynamic>> getSessionStats({
    String period = 'week',
  }) async {
    if (DataModeManager().isLocal) {
      return _local.getSessionStats(period: period);
    }

    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('${ApiService.baseUrl}/sessions/stats?period=$period'),
      headers: headers,
    ).timeout(ApiService.getTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('获取统计数据失败');
  }

  static Future<Map<String, dynamic>> getTodaySessionStats() async {
    if (DataModeManager().isLocal) return _local.getTodaySessionStats();

    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('${ApiService.baseUrl}/sessions/today'),
      headers: headers,
    ).timeout(ApiService.getTimeout);
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('获取今日统计失败');
  }
}
