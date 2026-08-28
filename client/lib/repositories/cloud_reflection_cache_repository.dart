import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/cloud_cache_db.dart';
import '../models/reflection_entry.dart';

/// Cloud Data Mode 下 Reflection / Observation 的追加型缓存。
///
/// Reflection 是第一方用户解释，离线时必须先落盘；待提交记录通过
/// sync_intents(reflections/create) 交给 CloudSyncCoordinator 补交 REST。
class CloudReflectionCacheRepository {
  final CloudCacheDb _cache = CloudCacheDb();

  Future<ReflectionEntry> createPending({
    required String content,
    required String entryType,
    String? questionId,
    String? dimensionKey,
    required Map<String, dynamic> context,
  }) async {
    final db = await _cache.database;
    final now = DateTime.now().toUtc().toIso8601String();
    late int localId;
    await db.transaction((txn) async {
      localId = await txn.insert('reflections', {
        'entry_type': entryType,
        'question_id': questionId,
        'dimension_key': dimensionKey,
        'content': content,
        'context_json': jsonEncode(context),
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
      await txn.insert(
        'sync_intents',
        {
          'entity_type': 'reflections',
          'entity_local_id': localId,
          'intent': 'create',
          'value': null,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return ReflectionEntry(
      id: -localId,
      entryType: entryType,
      questionId: questionId,
      dimensionKey: dimensionKey,
      content: content,
      context: context,
      createdAt: DateTime.parse(now).toLocal(),
    );
  }

  Future<void> cacheRemote(Iterable<ReflectionEntry> entries) async {
    final db = await _cache.database;
    await db.transaction((txn) async {
      for (final entry in entries) {
        if (entry.id <= 0) continue;
        final values = _remoteValues(entry);
        final existing = await txn.query(
          'reflections',
          columns: ['id'],
          where: 'server_id = ?',
          whereArgs: [entry.id],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert('reflections', values);
        } else {
          await txn.update(
            'reflections',
            values,
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        }
      }
    });
  }

  Future<List<ReflectionEntry>> recent({int limit = 20}) async {
    final db = await _cache.database;
    final rows = await db.query(
      'reflections',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> markCreateSynced(
    Database db,
    int localId,
    ReflectionEntry remote,
  ) async {
    final values = _remoteValues(remote);
    await db.transaction((txn) async {
      await txn.update(
        'reflections',
        values,
        where: 'id = ?',
        whereArgs: [localId],
      );
      await txn.delete(
        'sync_intents',
        where: 'entity_type = ? AND entity_local_id = ? AND intent = ?',
        whereArgs: ['reflections', localId, 'create'],
      );
    });
  }

  Map<String, Object?> _remoteValues(ReflectionEntry entry) => {
        'server_id': entry.id,
        'entry_type': entry.entryType,
        'question_id': entry.questionId,
        'dimension_key': entry.dimensionKey,
        'content': entry.content,
        'context_json': jsonEncode(entry.context),
        'created_at': entry.createdAt.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'synced',
      };

  ReflectionEntry _fromRow(Map<String, Object?> row) {
    Map<String, dynamic> context = const {};
    try {
      final decoded = jsonDecode(row['context_json']?.toString() ?? '{}');
      if (decoded is Map) context = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    final localId = row['id'] as int;
    final serverId = row['server_id'] as int?;
    return ReflectionEntry(
      id: serverId ?? -localId,
      entryType: row['entry_type'] as String? ?? 'reflection',
      questionId: row['question_id'] as String?,
      dimensionKey: row['dimension_key'] as String?,
      content: row['content'] as String? ?? '',
      context: context,
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
