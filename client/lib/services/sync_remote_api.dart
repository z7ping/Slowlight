import 'dart:convert';

import 'api_service.dart';
import 'http_util.dart';

/// SyncService 专用的 Cloud API。
/// 只服务显式 Cloud 同步，不参与 Data Mode 路由。
class SyncRemoteApi {
  const SyncRemoteApi._();

  static Future<Map<String, dynamic>> createSystemTag({
    required String name,
    required String icon,
    required String color,
    String? dimensionKey,
  }) async {
    final headers = await ApiService.authHeaders();
    final response = await HttpUtil.post(
      Uri.parse('${ApiService.baseUrl}/system-tags'),
      headers: headers,
      body: jsonEncode({
        'name': name,
        'icon': icon,
        'color': color,
        'dimension_key': dimensionKey ?? '',
      }),
    ).timeout(ApiService.postTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('创建观察标签失败: ${response.statusCode}');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  static Future<void> updateSystemTag(
    int id, {
    String? name,
    String? icon,
    String? color,
    String? dimensionKey,
  }) async {
    final headers = await ApiService.authHeaders();
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (icon != null) body['icon'] = icon;
    if (color != null) body['color'] = color;
    if (dimensionKey != null) body['dimension_key'] = dimensionKey;

    final response = await HttpUtil.put(
      Uri.parse('${ApiService.baseUrl}/system-tags/$id'),
      headers: headers,
      body: jsonEncode(body),
    ).timeout(ApiService.postTimeout);
    if (response.statusCode != 200) {
      throw Exception('更新观察标签失败: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> getChanges({String? since}) async {
    final headers = await ApiService.authHeaders();
    final uri = Uri.parse('${ApiService.baseUrl}/sync/changes').replace(
      queryParameters: since == null || since.isEmpty ? null : {'since': since},
    );
    final response = await HttpUtil.get(uri, headers: headers)
        .timeout(ApiService.getTimeout);
    if (response.statusCode != 200) {
      throw Exception('读取同步变更失败: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
