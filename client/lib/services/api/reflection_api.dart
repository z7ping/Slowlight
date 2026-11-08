import 'dart:convert';

import '../../models/reflection_entry.dart';
import '../api_service.dart';
import '../http_util.dart';

/// Reflection / Observation 的 Cloud REST 边界。
class ReflectionApi {
  static Future<ReflectionEntry> create({
    required String content,
    required String entryType,
    String? questionId,
    String? dimensionKey,
    Map<String, dynamic> context = const {},
    List<int> tagIds = const [],
    String? clientRequestId,
  }) async {
    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('${ApiService.baseUrl}/reflections'),
      headers: headers,
      body: jsonEncode({
        'entry_type': entryType,
        'question_id': questionId,
        'dimension_key': dimensionKey,
        'content': content,
        if (clientRequestId != null) 'client_request_id': clientRequestId,
        'tag_ids': tagIds,
        'context': context,
      }),
    ).timeout(ApiService.postTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('保存反思失败: ${response.statusCode}');
    }
    return ReflectionEntry.fromJson(
      Map<String, dynamic>.from(jsonDecode(response.body) as Map),
    );
  }

  /// Period submissions use one stable idempotency key across direct POST and
  /// deferred cloud sync, including when the server committed but ACK was lost.
  static String? periodClientRequestId(String? questionId) {
    if (questionId == null ||
        !(questionId.startsWith('review-week:') ||
            questionId.startsWith('review-30d:'))) {
      return null;
    }
    return 'period:$questionId';
  }

  static Future<List<ReflectionEntry>> recent({
    int limit = 20,
    int offset = 0,
    String? search,
    DateTime? startAt,
    DateTime? endAt,
    String? questionId,
    String? legacyWeekStart,
    String? legacyWeekEnd,
  }) async {
    final safeLimit = limit.clamp(1, 100).toInt();
    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('${ApiService.baseUrl}/reflections').replace(
        queryParameters: {
          'limit': '$safeLimit',
          if (startAt != null) 'start_at': startAt.toUtc().toIso8601String(),
          if (endAt != null) 'end_at': endAt.toUtc().toIso8601String(),
          if (offset > 0) 'offset': '$offset',
          if (search != null) 'search': search,
          if (questionId != null) 'question_id': questionId,
          if (legacyWeekStart != null) 'legacy_week_start': legacyWeekStart,
          if (legacyWeekEnd != null) 'legacy_week_end': legacyWeekEnd,
        },
      ),
      headers: headers,
    ).timeout(ApiService.getTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('获取反思记录失败: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    final values = decoded is Map ? decoded['items'] : decoded;
    if (startAt != null || endAt != null || search != null) {
      // A malformed paged month must not masquerade as a complete month.
      if (values is! List || values.any((item) => item is! Map)) {
        throw const FormatException('日历观察记录页格式错误');
      }
    }
    if (values is! List) return const [];
    return values
        .whereType<Map>()
        .map((item) => ReflectionEntry.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
  }
}
