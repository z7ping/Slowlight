import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../db/local_db.dart';
import '../db/local_product_core_schema.dart';
import '../models/dimension.dart';
import '../models/reflection_entry.dart';
import '../services/api/reflection_api.dart';
import '../services/cloud_sync_coordinator.dart';
import '../services/data_mode_manager.dart';
import 'cloud_reflection_cache_repository.dart';

/// Reflection / Observation 的统一数据边界。
///
/// Local Data → SQLite；Cloud Data → Server-first + account-scoped Cloud Cache。
/// 反思是用户解释自己数据的第一方数据，不属于 AI 配置，也不依赖 AI。
class ReflectionRepository {
  final CloudReflectionCacheRepository _cloudCache =
      CloudReflectionCacheRepository();

  Future<ReflectionEntry> create({
    required String content,
    String entryType = 'reflection',
    String? questionId,
    String? dimensionKey,
    Map<String, dynamic> context = const {},
  }) async {
    final normalized = content.trim();
    if (normalized.isEmpty) throw ArgumentError('反思内容不能为空');
    final type = _normalizeEntryType(entryType);
    final key = _normalizeDimensionKey(dimensionKey);
    if (DataModeManager().isLocal) {
      return _createLocal(
        content: normalized,
        entryType: type,
        questionId: questionId,
        dimensionKey: key,
        context: context,
      );
    }

    try {
      final remote = await ReflectionApi.create(
        content: normalized,
        entryType: type,
        questionId: questionId,
        dimensionKey: key,
        context: context,
      );
      await _cloudCache.cacheRemote([remote]);
      return remote;
    } catch (error) {
      if (!_isTransientNetworkError(error)) rethrow;
      final pending = await _cloudCache.createPending(
        content: normalized,
        entryType: type,
        questionId: questionId,
        dimensionKey: key,
        context: context,
      );
      await CloudSyncCoordinator().refreshStandalonePendingCount();
      unawaited(CloudSyncCoordinator().syncNow());
      return pending;
    }
  }

  Future<List<ReflectionEntry>> recent({int limit = 20}) async {
    final safeLimit = limit.clamp(1, 100).toInt();
    if (DataModeManager().isLocal) return _recentLocal(safeLimit);

    try {
      final remote = await ReflectionApi.recent(limit: safeLimit);
      await _cloudCache.cacheRemote(remote);
      // 从 cache 返回，确保尚未补交的离线 Reflection 不会因在线 GET 而暂时消失。
      return _cloudCache.recent(limit: safeLimit);
    } catch (error) {
      if (!_isTransientNetworkError(error)) rethrow;
      return _cloudCache.recent(limit: safeLimit);
    }
  }

  Future<ReflectionEntry> _createLocal({
    required String content,
    required String entryType,
    String? questionId,
    String? dimensionKey,
    required Map<String, dynamic> context,
  }) async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('reflections', {
      'entry_type': entryType,
      'question_id': questionId,
      'dimension_key': dimensionKey,
      'content': content,
      'context_json': jsonEncode(context),
      'created_at': now,
      'updated_at': now,
    });
    return ReflectionEntry(
      id: id,
      entryType: entryType,
      questionId: questionId,
      dimensionKey: dimensionKey,
      content: content,
      context: context,
      createdAt: DateTime.parse(now).toLocal(),
    );
  }

  Future<List<ReflectionEntry>> _recentLocal(int limit) async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final rows = await db.query(
      'reflections',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map((row) {
      Map<String, dynamic> context = const {};
      try {
        final decoded = jsonDecode(row['context_json'] as String? ?? '{}');
        if (decoded is Map) context = Map<String, dynamic>.from(decoded);
      } catch (_) {}
      return ReflectionEntry(
        id: row['id'] as int,
        entryType: row['entry_type'] as String? ?? 'reflection',
        questionId: row['question_id'] as String?,
        dimensionKey: row['dimension_key'] as String?,
        content: row['content'] as String? ?? '',
        context: context,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      );
    }).toList();
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

  String _normalizeEntryType(String value) {
    final normalized = value.trim().isEmpty ? 'reflection' : value.trim();
    if (normalized != 'reflection' && normalized != 'observation') {
      throw ArgumentError('entryType 仅支持 reflection / observation');
    }
    return normalized;
  }

  String? _normalizeDimensionKey(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (DimensionKey.fromValue(normalized) == null) {
      throw ArgumentError('无效的观察维度: $normalized');
    }
    return normalized;
  }
}
