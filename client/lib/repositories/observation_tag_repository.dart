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

typedef ObservationTagUsage = ({
  int tasks,
  int habits,
  int sessions,
  int reflections,
});

class ObservationTagDeletionUndo {
  ObservationTagDeletionUndo(this._restore);
  final Future<void> Function() _restore;
  bool _used = false;
  bool _busy = false;

  Future<void> restore() async {
    if (_used || _busy) throw StateError('这次撤销已执行或正在核对');
    _busy = true;
    try {
      await _restore();
      _used = true;
    } finally {
      _busy = false;
    }
  }
}

class _LocalTagDeletionSnapshot {
  const _LocalTagDeletionSnapshot({
    required this.tag,
    required this.taskIds,
    required this.habitIds,
    required this.sessionIds,
    required this.alias,
    required this.canonical,
    required this.links,
  });
  final Map<String, Object?> tag;
  final List<int> taskIds;
  final List<int> habitIds;
  final List<int> sessionIds;
  final Map<String, Object?>? alias;
  final Map<String, Object?>? canonical;
  final Map<String, List<Map<String, Object?>>> links;
}

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
      // Older servers return JSON null for an empty nil Go slice.
      if (value == null) return const [];
      if (value is! List) {
        throw const FormatException('标签列表响应格式错误');
      }
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

  /// Verified links that would be detached by deleting each managed label.
  /// A missing entry means not confirmed, never zero. Cloud is a single HTTP
  /// request; Local reuses its existing ID-aware, transactional link evidence.
  Future<Map<int, ObservationTagUsage>> getAssociationUsage(
      List<ObservationTag> tags) async {
    if (tags.isEmpty) return {};
    if (DataModeManager().isLocal) {
      final result = await Future.wait(tags.map(getDeletionImpact));
      return {
        for (var i = 0; i < tags.length; i++)
          if (result[i] != null) tags[i].id: result[i]!,
      };
    }
    final payload = await _cloudRequest('GET', '/system-tags/usage');
    if (payload is! Map || payload['counts'] is! Map) {
      throw const FormatException('标签关联响应格式错误');
    }
    final counts = payload['counts'] as Map;
    final result = <int, ObservationTagUsage>{};
    int? asCount(dynamic value) {
      if (value is! num || value < 0 || value % 1 != 0) return null;
      return value.toInt();
    }
    for (final tag in tags) {
      final raw = counts[tag.id.toString()];
      if (raw is! Map) continue;
      final tasks = asCount(raw['tasks']);
      final habits = asCount(raw['habits']);
      final sessions = asCount(raw['sessions']);
      final reflections = asCount(raw['reflections']);
      if (tasks == null || habits == null ||
          sessions == null || reflections == null) continue;
      result[tag.id] = (
        tasks: tasks,
        habits: habits,
        sessions: sessions,
        reflections: reflections,
      );
    }
    return result;
  }

  /// Counts only associations that the existing delete() actually detaches.
  /// Shared canonical tags survive; soft-deleted sources do not count.
  Future<ObservationTagUsage?> getDeletionImpact(ObservationTag tag) async {
    if (!DataModeManager().isLocal) {
      final usage = await getAssociationUsage([tag]);
      return usage[tag.id];
    }
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    return _localDeletionImpact(tag, db);
  }

  Future<ObservationTagUsage> _localDeletionImpact(
      ObservationTag tag, DatabaseExecutor db) async {
    final aliases = await db.query(
      'legacy_system_tag_aliases',
      columns: ['tag_id'],
      where: 'system_tag_id = ?',
      whereArgs: [tag.id],
      limit: 1,
    );
    var canonicalId = -1;
    if (aliases.isNotEmpty) {
      final linkedId = aliases.first['tag_id'] as int;
      final others = await db.rawQuery(
        'SELECT COUNT(*) AS total FROM legacy_system_tag_aliases '
        'WHERE tag_id = ? AND system_tag_id != ?',
        [linkedId, tag.id],
      );
      // Deleting a legacy alias shared by another managed label does not
      // remove the canonical label or its shared link rows.
      if ((others.first['total'] as num).toInt() == 0) {
        canonicalId = linkedId;
      }
    }

    // Count unique existing records, not stale link rows or soft-deleted
    // task/habit/reflection history. Avoid double counting legacy+canonical.
    Future<int> count(String entity, String links, String idColumn, {
      required bool legacy,
      required bool softDelete,
    }) async {
      final live = softDelete ? ' AND record.deleted_at IS NULL' : '';
      var sql = 'SELECT COUNT(*) AS total FROM ('
          'SELECT record.id AS entity_id FROM $entity record '
          'JOIN $links link ON link.$idColumn = record.id '
          'WHERE link.tag_id = ?$live';
      final args = <Object?>[canonicalId];
      if (legacy) {
        sql += ' UNION SELECT record.id AS entity_id FROM $entity record '
            'WHERE record.system_tag_id = ?$live';
        args.add(tag.id);
      }
      sql += ') linked';
      final rows = await db.rawQuery(sql, args);
      return (rows.first['total'] as num).toInt();
    }

    return (
      tasks: await count('tasks', 'task_tags', 'task_id',
          legacy: true, softDelete: true),
      habits: await count('habits', 'habit_tags', 'habit_id',
          legacy: true, softDelete: true),
      sessions: await count('work_sessions', 'work_session_tags',
          'work_session_id', legacy: true, softDelete: false),
      reflections: await count('reflections', 'reflection_tags',
          'reflection_id', legacy: false, softDelete: true),
    );
  }

  /// Save exact original tag/alias/link IDs before unlinking, in the SAME
  /// SQLite transaction. The in-memory receipt is used only by the 8s toast.
  Future<ObservationTagDeletionUndo> deleteWithUndo(
    ObservationTag tag, {required ObservationTagUsage expectedImpact}
  ) async {
    if (DataModeManager().isLocal) {
      final snapshot = await _deleteLocal(
        tag, expectedImpact: expectedImpact, undoable: true,
      );
      return ObservationTagDeletionUndo(
        () => _undoLocalTag(snapshot!),
      );
    }
    final payload = await _cloudRequest(
      'DELETE', '${_deletePath(tag, expectedImpact)}&undoable=true',
    );
    final token = payload is Map ? payload['undo_token'] as String? : null;
    if (token == null || token.length != 32) {
      throw StateError('标签删除结果可能已提交，但撤销凭据未确认，请刷新核对');
    }
    return ObservationTagDeletionUndo(() async {
      await _cloudRequest('POST', '/system-tags/undo',
        body: {'token': token});
    });
  }

  String _deletePath(ObservationTag tag, ObservationTagUsage? expected) {
    if (expected == null) return '/system-tags/${tag.id}';
    return '/system-tags/${tag.id}'
        '?expected_tasks=${expected.tasks}'
        '&expected_habits=${expected.habits}'
        '&expected_sessions=${expected.sessions}'
        '&expected_reflections=${expected.reflections}';
  }

  /// Compatibility for other call sites without an Undo notice.
  Future<void> delete(
    ObservationTag tag, {ObservationTagUsage? expectedImpact}
  ) async {
    if (tag.isDefault) throw StateError('默认观察标签不可删除');
    if (DataModeManager().isLocal) {
      await _deleteLocal(tag, expectedImpact: expectedImpact, undoable: false);
      return;
    }
    await _cloudRequest('DELETE', _deletePath(tag, expectedImpact));
  }

  Future<_LocalTagDeletionSnapshot?> _deleteLocal(
    ObservationTag tag, {
    required ObservationTagUsage? expectedImpact,
    required bool undoable,
  }) async {
    if (tag.isDefault) throw StateError('默认观察标签不可删除');
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    return db.transaction<_LocalTagDeletionSnapshot?>((txn) async {
      if (expectedImpact != null) {
        final current = await _localDeletionImpact(tag, txn);
        if (current != expectedImpact) {
          throw StateError('标签关联已发生变化，请重新核对删除范围');
        }
      }
      final snapshot = undoable
          ? await _captureLocalTag(txn, tag.id) : null;
      await txn.update('tasks', {'system_tag_id': null},
        where: 'system_tag_id = ?', whereArgs: [tag.id]);
      await txn.update('habits', {'system_tag_id': null},
        where: 'system_tag_id = ?', whereArgs: [tag.id]);
      await txn.update('work_sessions', {'system_tag_id': null},
        where: 'system_tag_id = ?', whereArgs: [tag.id]);
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
          await txn.delete('tags', where: 'id = ?',
            whereArgs: [canonicalId]);
        }
      }
      final removed = await txn.delete('system_tags',
        where: 'id = ?', whereArgs: [tag.id]);
      if (removed != 1) throw StateError('标签已变化，删除未确认');
      return snapshot;
    });
  }

  Future<_LocalTagDeletionSnapshot> _captureLocalTag(
    Transaction txn, int id,
  ) async {
    final tags = await txn.query('system_tags',
      where: 'id = ?', whereArgs: [id], limit: 1);
    if (tags.length != 1) throw StateError('标签已变化，请刷新后重试');

    Future<List<int>> legacyIds(String table) async {
      final rows = await txn.query(table, columns: ['id'],
        where: 'system_tag_id = ?', whereArgs: [id]);
      return rows.map((row) => row['id'] as int).toList(growable: false);
    }

    final aliases = await txn.query('legacy_system_tag_aliases',
      where: 'system_tag_id = ?', whereArgs: [id], limit: 1);
    final alias = aliases.isEmpty
        ? null : Map<String, Object?>.from(aliases.single);
    Map<String, Object?>? canonical;
    final links = <String, List<Map<String, Object?>>>{};
    if (alias != null) {
      final canonicalId = alias['tag_id'] as int;
      final otherAliases = await txn.query('legacy_system_tag_aliases',
        columns: ['system_tag_id'],
        where: 'tag_id = ? AND system_tag_id != ?',
        whereArgs: [canonicalId, id], limit: 1);
      if (otherAliases.isEmpty) {
        final rows = await txn.query('tags',
          where: 'id = ?', whereArgs: [canonicalId], limit: 1);
        if (rows.length != 1) {
          throw StateError('统一标签身份已变化，无法安全保存撤销证据');
        }
        canonical = Map<String, Object?>.from(rows.single);
        for (final table in [
          'task_tags', 'habit_tags', 'work_session_tags', 'reflection_tags',
        ]) {
          final rows = await txn.query(table,
            where: 'tag_id = ?', whereArgs: [canonicalId]);
          links[table] = rows.map((row) =>
            Map<String, Object?>.from(row)).toList(growable: false);
        }
      }
    }
    return _LocalTagDeletionSnapshot(
      tag: Map<String, Object?>.from(tags.single),
      taskIds: await legacyIds('tasks'),
      habitIds: await legacyIds('habits'),
      sessionIds: await legacyIds('work_sessions'),
      alias: alias,
      canonical: canonical,
      links: links,
    );
  }

  Future<void> _undoLocalTag(_LocalTagDeletionSnapshot snap) async {
    final db = await LocalDb().database;
    await db.transaction((txn) async {
      // A duplicate ID or a new label with the old name must not be
      // overwritten. SQLite constraints and transaction roll back together.
      if (snap.canonical != null) {
        await txn.insert('tags', snap.canonical!);
        for (final entry in snap.links.entries) {
          for (final link in entry.value) {
            await txn.insert(entry.key, link);
          }
        }
      }
      if (snap.alias != null) {
        if (snap.canonical == null) {
          final existing = await txn.query('tags',
            columns: ['id'], where: 'id = ?',
            whereArgs: [snap.alias!['tag_id']], limit: 1);
          if (existing.isEmpty) {
            throw StateError('共享标签身份已变化，不能安全撤销');
          }
        }
        await txn.insert('legacy_system_tag_aliases', snap.alias!);
      }
      await txn.insert('system_tags', snap.tag);

      Future<void> restoreIds(String table, List<int> ids) async {
        for (var start = 0; start < ids.length; start += 400) {
          final end = start + 400 > ids.length ? ids.length : start + 400;
          final chunk = ids.sublist(start, end);
          final placeholders = List.filled(chunk.length, '?').join(',');
          final changed = await txn.update(table,
            {'system_tag_id': snap.tag['id']},
            where: 'id IN ($placeholders) AND system_tag_id IS NULL',
            whereArgs: chunk);
          if (changed != chunk.length) {
            throw StateError('关联记录已变化，原标签删除不能撤销');
          }
        }
      }
      await restoreIds('tasks', snap.taskIds);
      await restoreIds('habits', snap.habitIds);
      await restoreIds('work_sessions', snap.sessionIds);
    });
  }

  Future<List<ObservationTag>> _getLocal() async {
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final rows = await db.query('system_tags',
        orderBy: 'created_at ASC, id ASC');
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
