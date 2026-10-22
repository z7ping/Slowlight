import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

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
      final cached = await _cloudCache.getObservationTags();
      // 无缓存不能伪装成“用户没有标签”，调用方需要提供重试入口。
      if (cached.isEmpty) rethrow;
      return cached;
    }
  }

  // Mirror old UI metadata to canonical label IDs without mixing namespaces.
  Future<void> _upsertLocalCanonical(
    Transaction txn, {
    required int legacyId,
    required String name,
    required String color,
    required String now,
  }) async {
    final aliases = await txn.query('legacy_system_tag_aliases',
        columns: ['tag_id'], where: 'system_tag_id = ?',
        whereArgs: [legacyId], limit: 1);
    int canonicalId;
    if (aliases.isNotEmpty) {
      canonicalId = aliases.first['tag_id'] as int;
    } else {
      final existing = await txn.query('tags',
          columns: ['id'], where: 'name = ?', whereArgs: [name],
          orderBy: 'id ASC', limit: 1);
      canonicalId = existing.isNotEmpty
          ? existing.first['id'] as int
          : await txn.insert('tags', {
              'name': name, 'color': color,
              'created_at': now, 'updated_at': now,
            });
      await txn.insert('legacy_system_tag_aliases', {
        'system_tag_id': legacyId, 'tag_id': canonicalId,
      });
    }
    final duplicate = await txn.query('tags', columns: ['id'],
        where: 'name = ? AND id != ?', whereArgs: [name, canonicalId],
        limit: 1);
    if (duplicate.isNotEmpty) throw StateError('同名标签已存在，请使用其他名称');
    final updated = await txn.update('tags',
        {'name': name, 'color': color, 'updated_at': now},
        where: 'id = ?', whereArgs: [canonicalId]);
    if (updated != 1) throw StateError('对应统一标签不存在');
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
      final created = await db.transaction((txn) async {
        final id = await txn.insert('system_tags', {
          'name': name.trim(), 'icon': icon, 'color': color,
          'dimension_key': key, 'is_default': 0,
          'created_at': now, 'updated_at': now,
        });
        await _upsertLocalCanonical(txn,
            legacyId: id, name: name.trim(), color: color, now: now);
        final rows = await txn.query('system_tags',
            where: 'id = ?', whereArgs: [id], limit: 1);
        return rows.first;
      });
      return ObservationTag.fromJson(Map<String, dynamic>.from(created));
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
      final updated = await db.transaction((txn) async {
        final count = await txn.update('system_tags', {
          'name': name.trim(), 'icon': icon, 'color': color,
          'dimension_key': key, 'updated_at': now,
        }, where: 'id = ?', whereArgs: [tag.id]);
        if (count != 1) throw StateError('观察标签不存在');
        await _upsertLocalCanonical(txn,
            legacyId: tag.id, name: name.trim(), color: color, now: now);
        final rows = await txn.query('system_tags',
            where: 'id = ?', whereArgs: [tag.id], limit: 1);
        return rows.first;
      });
      return ObservationTag.fromJson(Map<String, dynamic>.from(updated));
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
        final aliases = await txn.query('legacy_system_tag_aliases',
            columns: ['tag_id'], where: 'system_tag_id = ?',
            whereArgs: [tag.id], limit: 1);
        if (aliases.isNotEmpty) {
          final canonicalId = aliases.first['tag_id'] as int;
          await txn.delete('legacy_system_tag_aliases',
              where: 'system_tag_id = ?', whereArgs: [tag.id]);
          final others = await txn.query('legacy_system_tag_aliases',
              columns: ['tag_id'], where: 'tag_id = ?',
              whereArgs: [canonicalId], limit: 1);
          if (others.isEmpty) {
            for (final links in [
              'task_tags', 'habit_tags', 'work_session_tags', 'reflection_tags',
            ]) {
              await txn.delete(links,
                  where: 'tag_id = ?', whereArgs: [canonicalId]);
            }
            await txn.delete('tags', where: 'id = ?', whereArgs: [canonicalId]);
          }
        }
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
