import '../data_mode_manager.dart';
import '../local_api_service.dart';

/// 习惯相关 API
class HabitApi {
  static final _localApi = LocalApiService();

  /// 获取习惯列表
  static Future<List<Map<String, dynamic>>> getHabits() async {
    if (DataModeManager().isOffline) {
      return _localApi.getHabits();
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 创建习惯
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
  }) async {
    if (DataModeManager().isOffline) {
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
        showCheckinDialog: showCheckinDialog,
      );
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 打卡习惯
  static Future<Map<String, dynamic>> checkInHabit(
    int habitId, {
    String note = '',
    String? date,
  }) async {
    if (DataModeManager().isOffline) {
      return _localApi.checkInHabit(
        habitId,
        note: note,
        date: date,
      );
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 取消打卡
  static Future<Map<String, dynamic>> uncheckInHabit(int habitId) async {
    if (DataModeManager().isOffline) {
      return _localApi.uncheckInHabit(habitId);
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 获取习惯日志
  static Future<Map<String, dynamic>> getHabitLogs(
    int habitId, {
    String? month,
  }) async {
    if (DataModeManager().isOffline) {
      return _localApi.getHabitLogs(habitId, month: month);
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 删除习惯
  static Future<void> deleteHabit(int habitId) async {
    if (DataModeManager().isOffline) {
      return _localApi.deleteHabit(habitId);
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }
}
