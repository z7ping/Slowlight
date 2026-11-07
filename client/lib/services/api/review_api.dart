import 'dart:convert';

import '../api_service.dart';
import '../data_mode_manager.dart';
import '../http_util.dart';
import '../local_today_review_service.dart';
import '../local_today_timeline_service.dart';
import '../../models/today_timeline_item.dart';
import '../review_local_service.dart';
import 'analytics_api.dart';

/// Review 的唯一数据入口。
///
/// 页面只描述“我要回顾什么”，不再自己判断 Local / Cloud。
class ReviewApi {
  const ReviewApi._();

  static Future<Map<String, dynamic>> getTodayReview() async {
    if (DataModeManager().isLocal) {
      return LocalTodayReviewService().computeTodayReview();
    }
    return _getJson('/review/today');
  }

  static Future<List<TodayTimelineItem>> getTodayTimeline() async =>
      (await getPeriodTimeline()).items;

  /// One Local/Cloud evidence contract for today, this week and rolling
  /// 30 days. Observation count is not derived from the capped event list.
  static Future<ReviewPeriodTimeline> getPeriodTimeline({
    String period = 'today',
    int offset = 0,
    int limit = 40,
  }) async {
    if (period != 'today' && period != 'week' && period != 'month') {
      throw ArgumentError.value(period, 'period', 'Unsupported review period');
    }
    if (offset < 0 || offset > 1000000 || limit < 1 || limit > 40) {
      throw RangeError('Invalid review timeline page');
    }
    if (DataModeManager().isLocal) {
      return LocalTodayTimelineService().getPeriodTimeline(
        period: period, offset: offset, limit: limit,
      );
    }
    final data = await _getJson(
      '/review/today/timeline?period=$period&offset=$offset&limit=$limit',
    );
    return ReviewPeriodTimeline.fromJson(data);
  }

  static Future<Map<String, dynamic>> getTasksReview({int days = 7}) async {
    if (DataModeManager().isLocal) {
      return ReviewLocalService().computeTasksReview(days);
    }
    return _getJson('/review/tasks?days=$days');
  }

  static Future<Map<String, dynamic>> getOutputStats({String period = 'week'}) {
    return AnalyticsApi.getOutputStats(period: period);
  }

  static Future<Map<String, dynamic>> _getJson(String path) async {
    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('${ApiService.baseUrl}$path'),
      headers: headers,
    ).timeout(ApiService.getTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('获取回顾数据失败: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw StateError('Review API response must be object');
    return Map<String, dynamic>.from(decoded);
  }
}
