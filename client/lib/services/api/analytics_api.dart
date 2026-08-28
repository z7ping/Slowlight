import 'dart:convert';

import '../api_service.dart';
import '../data_mode_manager.dart';
import '../http_util.dart';
import '../local_analytics_service.dart';
import '../local_analytics_stats.dart';
import '../local_dimension_analytics.dart';

/// 分析统计统一入口。
///
/// Data Mode 只决定数据来源：
/// - Local → SQLite analytics
/// - Cloud → Slowlight Server analytics endpoints
class AnalyticsApi {
  static final LocalAnalyticsService _local = LocalAnalyticsService();
  static final LocalDimensionAnalytics _dimensions = LocalDimensionAnalytics();

  static Future<List<Map<String, dynamic>>> getDailyTrend({int days = 7}) async {
    if (DataModeManager().isLocal) {
      return _local.getDailyTrend(days: days);
    }
    final data = await _getJson('/analytics/daily-trend?days=$days');
    final values = data['days'];
    return values is List
        ? values.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
  }

  static Future<Map<String, dynamic>> getTimeDistribution() async {
    if (DataModeManager().isLocal) return _local.getTimeDistribution();
    return _getJson('/analytics/time-distribution');
  }

  static Future<Map<String, dynamic>> getWeeklyReview() async {
    if (DataModeManager().isLocal) return _local.getWeeklyReview();
    return _getJson('/analytics/weekly-review');
  }

  static Future<Map<String, dynamic>> getOutputStats({String period = 'all'}) async {
    if (DataModeManager().isLocal) {
      return _local.getOutputStats(period: period);
    }
    return _getJson('/analytics/output?period=$period');
  }

  /// 顶层四维度是稳定产品坐标，不再等同于用户可编辑 SystemTag。
  static Future<Map<String, dynamic>> getDimensionSummary() async {
    if (DataModeManager().isLocal) return _dimensions.getSummary();
    return _getJson('/analytics/dimension-summary');
  }

  static Future<Map<String, dynamic>> getTaskStats() async {
    if (DataModeManager().isLocal) return _local.getTaskStats();
    return _getJson('/tasks/stats');
  }

  static Future<List<dynamic>> getListStats() async {
    if (DataModeManager().isLocal) return _local.getListStats();
    final value = await _getAny('/lists/stats');
    return value is List ? value : <dynamic>[];
  }

  static Future<List<dynamic>> getTagStats() async {
    if (DataModeManager().isLocal) return _local.getTagStats();
    final value = await _getAny('/tags/stats');
    return value is List ? value : <dynamic>[];
  }

  /// Reminder 仍有独立业务模型；这里只保持 StatsScreen API 可用。
  static Future<Map<String, dynamic>> getReminderStats({String period = 'week'}) async {
    if (DataModeManager().isLocal) {
      return {
        'total_work_seconds': 0,
        'total_break_seconds': 0,
        'work_count': 0,
        'rest_count': 0,
        'skipped_count': 0,
        'is_active': false,
      };
    }
    return _getJson('/reminder/stats?period=$period');
  }

  static Future<Map<String, dynamic>> _getJson(String path) async {
    final value = await _getAny(path);
    if (value is Map) return Map<String, dynamic>.from(value);
    throw StateError('Expected object response from $path');
  }

  static Future<dynamic> _getAny(String path) async {
    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('${ApiService.baseUrl}$path'),
      headers: headers,
    ).timeout(ApiService.getTimeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }
    throw Exception('获取分析数据失败: ${response.statusCode}');
  }
}
