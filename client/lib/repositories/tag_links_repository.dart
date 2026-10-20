import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/local_db.dart';
import '../db/local_product_core_schema.dart';
import '../models/tag.dart';
import '../services/api_service.dart';
import '../services/data_mode_manager.dart';
import '../services/http_util.dart';

/// 统一标签关联的实体。历史 observation / reflection 共用 reflections 表。
enum TagLinkedEntity { task, habit, session, observation, reflection }

typedef _LinkSpec = ({String table, String links, String foreignKey, bool softDelete});

_LinkSpec _linkSpec(TagLinkedEntity entity) => switch (entity) {
      TagLinkedEntity.task => (
          table: 'tasks',
          links: 'task_tags',
          foreignKey: 'task_id',
          softDelete: true,
        ),
      TagLinkedEntity.habit => (
          table: 'habits',
          links: 'habit_tags',
          foreignKey: 'habit_id',
          softDelete: true,
        ),
      TagLinkedEntity.session => (
          table: 'work_sessions',
          links: 'work_session_tags',
          foreignKey: 'work_session_id',
          softDelete: false,
        ),
      TagLinkedEntity.observation || TagLinkedEntity.reflection => (
          table: 'reflections',
          links: 'reflection_tags',
          foreignKey: 'reflection_id',
          softDelete: true,
        ),
    };

/// 跨 Local / Cloud Data Mode 的统一标签关联仓储。
///
/// 仅管理 canonical tags 的多对多关系；不读写 legacy system_tag_id，
/// 也不将 Cloud ID 当作 SQLite ID。Cloud 写入必须得到服务器确认，
/// 断网时不退回本地库，避免把云端修改误写进另一数据模式。
class TagLinksRepository {
  Future<List<Tag>> getFor(TagLinkedEntity entity, int recordId) async {
    _requireRecordId(recordId);
    if (DataModeManager().isLocal) {
      await LocalProductCoreSchema.ensureReady();
      final db = await LocalDb().database;
      final spec = _linkSpec(entity);
      await _ensureLocalRecord(db, spec, recordId);
      return _localList(db, spec, recordId);
    }
    return _cloudRequest('GET', entity, recordId);
  }

  /// 完整替换当前记录关联；空数组代表明确清空。
  /// 严格验证后才落盘，不会因错误 ID 清掉现有关联。
  Future<List<Tag>> replaceFor(
    TagLinkedEntity entity,
    int recordId,
    List<int> tagIds,
  ) async {
    _requireRecordId(recordId);
    if (tagIds.length > 64 || tagIds.any((id) => id <= 0)) {
      throw ArgumentError.value(tagIds, 'tagIds', '标签 ID 必须为正整数，最多 64 个');
    }
    final uniqueIds = tagIds.toSet().toList(growable: false);
    if (!DataModeManager().isLocal) {
      return _cloudRequest('PUT', entity, recordId, tagIds: uniqueIds);
    }

    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final spec = _linkSpec(entity);
    return db.transaction((txn) async {
      await _ensureLocalRecord(txn, spec, recordId);
      if (uniqueIds.isNotEmpty) {
        final placeholders = List.filled(uniqueIds.length, '?').join(',');
        final rows = await txn.rawQuery(
          'SELECT id FROM tags WHERE id IN ($placeholders)',
          uniqueIds,
        );
        if (rows.length != uniqueIds.length) {
          throw StateError('标签不存在，关联未修改');
        }
      }
      await txn.delete(
        spec.links,
        where: '${spec.foreignKey} = ?',
        whereArgs: [recordId],
      );
      for (final tagId in uniqueIds) {
        await txn.insert(spec.links, {
          spec.foreignKey: recordId,
          'tag_id': tagId,
        });
      }
      return _localList(txn, spec, recordId);
    });
  }

  void _requireRecordId(int id) {
    if (id <= 0) throw ArgumentError.value(id, 'recordId', '记录 ID 必须为正整数');
  }

  Future<void> _ensureLocalRecord(
    DatabaseExecutor db,
    _LinkSpec spec,
    int id,
  ) async {
    final rows = await db.query(
      spec.table,
      columns: ['id'],
      where: 'id = ?${spec.softDelete ? ' AND deleted_at IS NULL' : ''}',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('记录不存在');
  }

  Future<List<Tag>> _localList(
    DatabaseExecutor db,
    _LinkSpec spec,
    int recordId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT tags.id, tags.name, tags.color, tags.created_at '
      'FROM tags JOIN ${spec.links} ON tags.id = ${spec.links}.tag_id '
      'WHERE ${spec.links}.${spec.foreignKey} = ? '
      'ORDER BY tags.created_at ASC, tags.id ASC',
      [recordId],
    );
    return rows
        .map((row) => Tag.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<Tag>> _cloudRequest(
    String method,
    TagLinkedEntity entity,
    int recordId, {
    List<int>? tagIds,
  }) async {
    final uri = Uri.parse(
      '${ApiService.baseUrl}/tag-links/${entity.name}/$recordId',
    );
    final headers = await ApiService.authHeaders();
    final response = method == 'GET'
        ? await HttpUtil.get(uri, headers: headers)
            .timeout(ApiService.getTimeout)
        : await HttpUtil.put(
            uri,
            headers: headers,
            body: jsonEncode({'tag_ids': tagIds}),
          ).timeout(ApiService.postTimeout);
    if (response.statusCode != 200) {
      throw StateError(
        response.statusCode == 404 ? '记录不存在' : '标签关联${method == 'GET' ? '读取' : '保存'}失败（${response.statusCode}）',
      );
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final values = payload['tags'];
    if (values is! List) throw const FormatException('标签响应格式错误');
    return values
        .map((item) => Tag.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }
}
