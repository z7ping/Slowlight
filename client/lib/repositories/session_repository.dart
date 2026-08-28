import '../services/api/session_api.dart';

/// WorkSession Repository。
///
/// 由 SessionApi 根据 Data Mode 选择 Local SQLite 或 Slowlight Server，
/// 调用方不再关心会话数据具体存在哪里。
class SessionRepository {
  Future<Map<String, dynamic>> startSession(
    String sessionType, {
    int? taskId,
    String device = 'desktop',
  }) =>
      SessionApi.startSession(
        sessionType,
        taskId: taskId,
        device: device,
      );

  Future<Map<String, dynamic>> endSession({int? systemTagId}) =>
      SessionApi.endSession(systemTagId: systemTagId);

  Future<Map<String, dynamic>> getActiveSession() =>
      SessionApi.getActiveSession();

  Future<Map<String, dynamic>> getSessionStats({
    String period = 'week',
  }) =>
      SessionApi.getSessionStats(period: period);

  Future<Map<String, dynamic>> getTodaySessionStats() =>
      SessionApi.getTodaySessionStats();
}
