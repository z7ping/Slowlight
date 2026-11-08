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
import '../utils/habit_record_key.dart';
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
    List<int> tagIds = const [],
  }) async {
    final normalized = content.trim();
    if (normalized.isEmpty) throw ArgumentError('反思内容不能为空');
    if (tagIds.length > 64 || tagIds.any((id) => id <= 0)) {
      throw ArgumentError.value(tagIds, 'tagIds', '最多 64 个有效标签 ID');
    }
    final uniqueTagIds = tagIds.toSet().toList(growable: false);
    // One opaque identity must survive a lost direct POST response and its
    // offline queued replay; the server already deduplicates client_request_id.
    final clientRequestId = ReflectionApi.periodClientRequestId(questionId) ??
        'reflection:${createHabitRecordKey()}';
    final type = _normalizeEntryType(entryType);
    final key = _normalizeDimensionKey(dimensionKey);
    if (DataModeManager().isLocal) {
      return _createLocal(
        content: normalized,
        entryType: type,
        questionId: questionId,
        dimensionKey: key,
        context: context,
        tagIds: uniqueTagIds,
      );
    }

    try {
      final remote = await ReflectionApi.create(
        content: normalized,
        entryType: type,
        questionId: questionId,
        dimensionKey: key,
        context: context,
        tagIds: uniqueTagIds,
        clientRequestId: clientRequestId,
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
        tagIds: uniqueTagIds,
        clientRequestId: clientRequestId,
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

  /// Search first-party history, not just recent(100).
  /// Bounded results are marked incomplete when more exist.
  Future<({List<ReflectionEntry> entries, bool complete})> searchContent(
      String keyword) async {
    final term = keyword.trim();
    if (term.isEmpty || term.runes.length > 200) {
      throw ArgumentError.value(keyword, 'keyword', '关键词应为 1–200 字');
    }
    final literal = term.toLowerCase()
        .replaceAll('!', '!!')
        .replaceAll('%', '!%')
        .replaceAll('_', '!_');
    if (DataModeManager().isLocal) {
      await LocalProductCoreSchema.ensureReady();
      final db = await LocalDb().database;
      final rows = await db.query(
        'reflections',
        where: "deleted_at IS NULL AND LOWER(content) LIKE ? ESCAPE '!'",
        whereArgs: ['%$literal%'],
        orderBy: 'created_at DESC, id DESC',
        limit: 501,
      );
      return (
        entries: rows.take(500).map(_fromLocalRow).toList(growable: false),
        complete: rows.length <= 500,
      );
    }

    final fetched = <ReflectionEntry>[];
    try {
      final ids = <int>{};
      const pageSize = 100;
      for (var offset = 0; offset <= 500; offset += pageSize) {
        final page = await ReflectionApi.recent(
          search: term,
          offset: offset,
          limit: pageSize,
        );
        // An old server may ignore the keyword and return unrelated data.
        if (page.any((entry) =>
            entry.id <= 0 ||
            !entry.content.toLowerCase().contains(term.toLowerCase()) ||
            !ids.add(entry.id))) {
          throw const FormatException('服务端不支持完整历史检索');
        }
        fetched.addAll(page);
        if (page.length < pageSize) {
          await _cloudCache.cacheRemote(fetched);
          final pending = await _cloudCache.searchContent(
            term, pendingOnly: true,
          );
          final merged = <int, ReflectionEntry>{
            // Local unsynced observations must remain reachable even when
            // the remote 500-entry result cap is hit.
            for (final entry in pending) entry.id: entry,
            for (final entry in fetched) entry.id: entry,
          };
          return (
            entries: merged.values.take(500).toList(growable: false),
            complete: merged.length <= 500,
          );
        }
        if (fetched.length == 500) break;
      }
      final pending = await _cloudCache.searchContent(
        term, pendingOnly: true,
      );
      final merged = <int, ReflectionEntry>{
        for (final entry in pending) entry.id: entry,
        for (final entry in fetched) entry.id: entry,
      };
      return (
        entries: merged.values.take(500).toList(growable: false),
        complete: false,
      );
    } catch (error) {
      if (!_isTransientNetworkError(error) && error is! FormatException) {
        rethrow;
      }
      final cached = await _cloudCache.searchContent(term);
      final merged = <int, ReflectionEntry>{
        for (final entry in cached) entry.id: entry,
        for (final entry in fetched) entry.id: entry,
      };
      return (
        entries: merged.values.take(500).toList(growable: false),
        complete: false,
      );
    }
  }

  /// Exact civil-calendar month rather than an unreliable recent(100)
  /// sample. A Cloud cache fallback is explicitly incomplete.
  Future<({List<ReflectionEntry> entries, bool complete})> month(
      DateTime month) async {
    final start = DateTime(month.year, month.month).toUtc();
    final end = DateTime(month.year, month.month + 1).toUtc();
    if (DataModeManager().isLocal) {
      await LocalProductCoreSchema.ensureReady();
      final db = await LocalDb().database;
      final rows = await db.query(
        'reflections',
        where: 'deleted_at IS NULL AND created_at >= ? AND created_at < ?',
        whereArgs: [
          start.toIso8601String(),
          end.toIso8601String(),
        ],
        orderBy: 'created_at DESC, id DESC',
      );
      return (
        entries: rows.map(_fromLocalRow).toList(growable: false),
        complete: true,
      );
    }

    final fetched = <ReflectionEntry>[];
    try {
      final fetchedIds = <int>{};
      const pageSize = 100;
      for (var offset = 0; ; offset += pageSize) {
        if (offset >= 100000) {
          throw StateError('单月观察记录数量超出安全分页范围');
        }
        final page = await ReflectionApi.recent(
          limit: pageSize,
          offset: offset,
          startAt: start,
          endAt: end,
        );
        // Detect older Cloud endpoints which do not recognize ranges.
        if (page.any((item) =>
            item.createdAt.isBefore(start) ||
            !item.createdAt.isBefore(end))) {
          throw const FormatException('服务器未返回指定月份的观察记录');
        }
        if (page.any((item) => !fetchedIds.add(item.id))) {
          throw const FormatException('日历观察分页未推进，不能确认完整历史');
        }
        fetched.addAll(page);
        if (page.length < pageSize) break;
      }
      await _cloudCache.cacheRemote(fetched);
      final pending = await _cloudCache.month(
        start, end, pendingOnly: true,
      );
      final byId = <int, ReflectionEntry>{
        for (final entry in fetched) entry.id: entry,
        for (final entry in pending) entry.id: entry,
      };
      return (entries: byId.values.toList(growable: false), complete: true);
    } catch (error) {
      if (!_isTransientNetworkError(error) && error is! FormatException) {
        rethrow;
      }
      // Old or malformed pagination cannot prove a complete month. Keep
      // confirmed cache facts but mark the calendar source as incomplete.
      final cached = await _cloudCache.month(start, end);
      final confirmed = <int, ReflectionEntry>{
        for (final entry in cached) entry.id: entry,
        // Preserve valid pages fetched before the failed network request.
        for (final entry in fetched) entry.id: entry,
      };
      return (
        entries: confirmed.values.toList(growable: false),
        complete: false,
      );
    }
  }

  /// Exact period lookup. Never infer absence from a recent(100) window.
  /// A successful Cloud GET is required before an absent response is trusted.
  Future<ReflectionEntry?> findPeriodResponse(
    String questionId, {
    String? legacyWeekStart,
    String? legacyWeekEnd,
  }) async {
    if (questionId.trim().isEmpty) {
      throw ArgumentError.value(questionId, 'questionId');
    }
    if (DataModeManager().isLocal) {
      return _findLocalPeriodResponse(
        questionId,
        legacyWeekStart: legacyWeekStart,
        legacyWeekEnd: legacyWeekEnd,
      );
    }
    final remote = await ReflectionApi.recent(
      limit: 1,
      questionId: questionId,
      legacyWeekStart: legacyWeekStart,
      legacyWeekEnd: legacyWeekEnd,
    );
    await _cloudCache.cacheRemote(remote);
    if (remote.isNotEmpty) return remote.first;
    // The server returned no confirmed response, but an offline submission
    // can still be pending in the account-scoped cache.
    return _cloudCache.pendingByQuestionId(questionId);
  }

  Future<ReflectionEntry?> _findLocalPeriodResponse(
    String questionId, {
    String? legacyWeekStart,
    String? legacyWeekEnd,
  }) async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final legacy = legacyWeekStart != null && legacyWeekEnd != null;
    final rows = await db.query(
      'reflections',
      where: legacy
          ? 'deleted_at IS NULL AND entry_type = \'reflection\' AND (question_id = ? OR '
              '((question_id IS NULL OR question_id = \'\') AND '
              'entry_type = ? AND context_json LIKE ? AND '
              'context_json LIKE ? AND context_json LIKE ?))'
          : 'deleted_at IS NULL AND entry_type = \'reflection\' AND question_id = ?',
      whereArgs: legacy
          ? [
              questionId,
              'reflection',
              '%"source":"weekly_review"%',
              '%"week_start":"$legacyWeekStart"%',
              '%"week_end":"$legacyWeekEnd"%',
            ]
          : [questionId],
      orderBy: 'created_at DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _fromLocalRow(rows.first);
  }

  Future<ReflectionEntry> _createLocal({
    required String content,
    required String entryType,
    String? questionId,
    String? dimensionKey,
    required Map<String, dynamic> context,
    required List<int> tagIds,
  }) async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final now = DateTime.now().toUtc().toIso8601String();
    return db.transaction((txn) async {
      if (tagIds.isNotEmpty) {
        final placeholders = List.filled(tagIds.length, '?').join(',');
        final matches = await txn.rawQuery(
          'SELECT id FROM tags WHERE id IN ($placeholders)',
          tagIds,
        );
        if (matches.length != tagIds.length) {
          throw StateError('标签不存在，观察记录未保存');
        }
      }
      final id = await txn.insert('reflections', {
        'entry_type': entryType,
        'question_id': questionId,
        'dimension_key': dimensionKey,
        'content': content,
        'context_json': jsonEncode(context),
        'created_at': now,
        'updated_at': now,
      });
      for (final tagId in tagIds) {
        await txn.insert('reflection_tags', {
          'reflection_id': id,
          'tag_id': tagId,
        });
      }
      return ReflectionEntry(
        id: id,
        entryType: entryType,
        questionId: questionId,
        dimensionKey: dimensionKey,
        content: content,
        context: context,
        createdAt: DateTime.parse(now).toLocal(),
      );
    });
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
    return rows.map(_fromLocalRow).toList();
  }

  ReflectionEntry _fromLocalRow(Map<String, Object?> row) {
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
