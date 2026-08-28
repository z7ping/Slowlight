import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../db/local_db.dart';
import '../db/local_product_core_schema.dart';
import '../models/dimension.dart';
import '../models/observation_tag.dart';
import '../services/api_service.dart';
import '../services/data_mode_manager.dart';
import '../services/http_util.dart';
import 'cloud_reference_cache_repository.dart';

/// 用户可编辑的观察标签数据边界。
///
/// ObservationTag 可以选择归属某个固定 Dimension，但它本身不是 Dimension。
class ObservationTagRepository {
  final CloudReferenceCacheRepository _cloudCache =
      CloudReferenceCacheRepository();

  Future<List<ObservationTag>> getAll() async {
    if (DataModeManager().isLocal) return _getLocal();
    try {
      final value = await _cloudRequest('GET', '/system-tags');
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((item) => ObservationTag.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList();
    } catch (error) {
      if (!_isTransientNetworkError(error)) rethrow;
      return _cloudCache.getObservationTags();
    }
  }

  Future<ObservationTag> create({
    required String name,
    required String icon,
    required String color,
    String? dimensionKey,
  }) async {
    final key = _normalizeDimensionKey(dimensionKey);
    if (DataModeManager().isLocal) {
      await LocalProductCoreSchema.ensureReady();
      final db = await LocalDb().database;
      final now = DateTime.now().toUtc().toIso8601String();
      final id = await db.insert('system_tags', {
        'name': name.trim(),
        'icon': icon,
        'color': color,
        'dimension_key': key,
        'is_default': 0,
        'created_at': now,
        'updated_at': now,
      });
      final rows = await db.query(
        'system_tags',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return ObservationTag.fromJson(Map<String, dynamic>.from(rows.first));
    }

    final value = await _cloudRequest('POST', '/system-tags', body: {
      'name': name.trim(),
      'icon': icon,
      'color': color,
      'dimension_key': key,
    });
    return ObservationTag.fromJson(Map<String, dynamic>.from(value as Map));
  }

  Future<ObservationTag> update(
    ObservationTag tag, {
    required String name,
    required String icon,
    required String color,
    String? dimensionKey,
  }) async {
    final key = _normalizeDimensionKey(dimensionKey);
    if (DataModeManager().isLocal) {
      await LocalProductCoreSchema.ensureReady();
      final db = await LocalDb().database;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.update(
        'system_tags',
        {
          'name': name.trim(),
          'icon': icon,
          'color': color,
          'dimension_key': key,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [tag.id],
      );
      final rows = await db.query(
        'system_tags',
        where: 'id = ?',
        whereArgs: [tag.id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('观察标签不存在');
      return ObservationTag.fromJson(Map<String, dynamic>.from(rows.first));
    }

    final value = await _cloudRequest('PUT', '/system-tags/${tag.id}', body: {
      'name': name.trim(),
      'icon': icon,
      'color': color,
      'dimension_key': key,
    });
    return ObservationTag.fromJson(Map<String, dynamic>.from(value as Map));
  }

  Future<void> delete(ObservationTag tag) async {
    if (tag.isDefault) throw StateError('默认观察标签不可删除');
    if (DataModeManager().isLocal) {
      await LocalProductCoreSchema.ensureReady();
      final db = await LocalDb().database;
      await db.transaction((txn) async {
        await txn.update(
          'tasks',
          {'system_tag_id': null},
          where: 'system_tag_id = ?',
          whereArgs: [tag.id],
        );
        await txn.update(
          'habits',
          {'system_tag_id': null},
          where: 'system_tag_id = ?',
          whereArgs: [tag.id],
        );
        await txn.delete('system_tags', where: 'id = ?', whereArgs: [tag.id]);
      });
      return;
    }
    await _cloudRequest('DELETE', '/system-tags/${tag.id}');
  }

  Future<List<ObservationTag>> _getLocal() async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final rows = await db.query('system_tags', orderBy: 'created_at ASC');
    return rows
        .map((row) => ObservationTag.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  bool _isTransientNetworkError(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException) {
      return true;
    }
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('timeoutexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('network is unreachable') ||
        text.contains('clientexception');
  }

  String _normalizeDimensionKey(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return '';
    if (DimensionKey.fromValue(normalized) == null) {
      throw ArgumentError('无效的观察维度: $normalized');
    }
    return normalized;
  }

  Future<dynamic> _cloudRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final headers = await ApiService.authHeaders();
    final uri = Uri.parse('${ApiService.baseUrl}$path');
    final encoded = body == null ? null : jsonEncode(body);
    final response = switch (method) {
      'GET' => await HttpUtil.get(uri, headers: headers)
          .timeout(ApiService.getTimeout),
      'POST' => await HttpUtil.post(uri, headers: headers, body: encoded)
          .timeout(ApiService.postTimeout),
      'PUT' => await HttpUtil.put(uri, headers: headers, body: encoded)
          .timeout(ApiService.postTimeout),
      'DELETE' => await HttpUtil.delete(uri, headers: headers)
          .timeout(ApiService.postTimeout),
      _ => throw ArgumentError('Unsupported method: $method'),
    };
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = '观察标签请求失败: ${response.statusCode}';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] != null) {
          message = decoded['error'].toString();
        }
      } catch (_) {}
      throw Exception(message);
    }
    if (response.body.trim().isEmpty) return const <String, dynamic>{};
    return jsonDecode(response.body);
  }
}
