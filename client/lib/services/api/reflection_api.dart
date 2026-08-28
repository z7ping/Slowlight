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

  static Future<List<ReflectionEntry>> recent({int limit = 20}) async {
    final safeLimit = limit.clamp(1, 100).toInt();
    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.get(
      Uri.parse('${ApiService.baseUrl}/reflections?limit=$safeLimit'),
      headers: headers,
    ).timeout(ApiService.getTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('获取反思记录失败: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    final values = decoded is Map ? decoded['items'] : decoded;
    if (values is! List) return const [];
    return values
        .whereType<Map>()
        .map((item) => ReflectionEntry.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
  }
}
