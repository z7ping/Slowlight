import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/local_db.dart';
import '../db/local_product_core_schema.dart';
import '../services/api_service.dart';
import '../services/data_mode_manager.dart';
import '../services/http_util.dart';

/// 统一标签与记录的多对多关联。只接受统一 tags.id，不能传 legacy system_tags.id。
///
/// Cloud Data 暂时只允许已上云记录且在线保存，不对负数临时 ID 或离线变更
/// 假装保存成功。后续完善待同步关联协议后才可开放全平台离线编辑。
enum TagRecordKind { task, habit, session, observation }

class TagLinksRepository {
  const TagLinksRepository();

  static const _links = <TagRecordKind, ({String entity, String table, String key, String records})>{
    TagRecordKind.task: (
      entity: 'task', table: 'task_tags', key: 'task_id', records: 'tasks',
    ),
    TagRecordKind.habit: (
      entity: 'habit', table: 'habit_tags', key: 'habit_id', records: 'habits',
    ),
    TagRecordKind.session: (
      entity: 'session', table: 'work_session_tags', key: 'work_session_id',
      records: 'work_sessions',
    ),
    TagRecordKind.observation: (
      entity: 'observation', table: 'reflection_tags', key: 'reflection_id',
      records: 'reflections',
    ),
  };

  Future<List<int>> getTagIds(TagRecordKind kind, int recordId) async {
    if (recordId == 0) throw ArgumentError.value(recordId, 'recordId');
    if (DataModeManager().isCloud) {
      _requireCloudId(recordId);
      final response = await HttpUtil.get(
        Uri.parse('${ApiService.baseUrl}/tag-links/${_links[kind]!.entity}/$recordId'),
        headers: await ApiService.authHeaders(),
      ).timeout(ApiService.getTimeout);
      if (response.statusCode != 200) {
        throw StateError('获取记录标签失败（${response.statusCode}）');
      }
      final payload = jsonDecode(response.body);
      if (payload is! Map || payload['tag_ids'] is! List) {
        throw FormatException('标签响应格式错误');
      }
      final values = (payload['tag_ids'] as List);
      if (values.any((id) => id is! int || id <= 0)) {
        throw FormatException('标签 ID 格式错误');
      }
      return values.cast<int>();
    }
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final spec = _links[kind]!;
    await _requireLocalRecord(db, spec.records, recordId);
    final rows = await db.rawQuery(
      'SELECT t.id FROM tags AS t '
      'JOIN ${spec.table} AS links ON links.tag_id = t.id '
      'WHERE links.${spec.key} = ? ORDER BY t.created_at ASC, t.id ASC',
      [recordId],
    );
    return rows.map((row) => row['id'] as int).toList(growable: false);
  }

  Future<void> replace(
    TagRecordKind kind,
    int recordId,
    List<int> tagIds,
  ) async {
    if (recordId == 0) throw ArgumentError.value(recordId, 'recordId');
    final unique = tagIds.toSet().toList(growable: false);
    if (unique.length > 64 || unique.any((id) => id <= 0)) {
      throw ArgumentError.value(tagIds, 'tagIds', '最多 64 个有效标签 ID');
    }
    if (DataModeManager().isCloud) {
      _requireCloudId(recordId);
      final response = await HttpUtil.put(
        Uri.parse('${ApiService.baseUrl}/tag-links/${_links[kind]!.entity}/$recordId'),
        headers: await ApiService.authHeaders(),
        body: jsonEncode({'tag_ids': unique}),
      ).timeout(ApiService.postTimeout);
      if (response.statusCode != 200) {
        throw StateError('保存记录标签失败（${response.statusCode}）');
      }
      return;
    }
    await LocalProductCoreSchema.ensureReady();
    final db = await LocalDb().database;
    final spec = _links[kind]!;
    await db.transaction((txn) async {
      await _requireLocalRecord(txn, spec.records, recordId);
      if (unique.isNotEmpty) {
        final placeholders = List.filled(unique.length, '?').join(',');
        final result = await txn.rawQuery(
          'SELECT COUNT(*) AS count FROM tags WHERE id IN ($placeholders)',
          unique,
        );
        if (result.first['count'] != unique.length) {
          throw StateError('包含不存在的标签，已取消保存');
        }
      }
      await txn.delete(spec.table, where: '${spec.key} = ?', whereArgs: [recordId]);
      for (final tagId in unique) {
        await txn.insert(
          spec.table,
          {spec.key: recordId, 'tag_id': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  void _requireCloudId(int recordId) {
    if (recordId < 0) {
      throw StateError('该记录尚未同步，暂不能修改标签；原有关联不会丢失');
    }
  }

  Future<void> _requireLocalRecord(
    DatabaseExecutor db,
    String table,
    int id,
  ) async {
    final where = table == 'work_sessions'
        ? 'id = ?'
        : 'id = ? AND deleted_at IS NULL';
    final values = await db.query(table, columns: ['id'], where: where, whereArgs: [id], limit: 1);
    if (values.isEmpty) throw StateError('记录不存在，已取消标签修改');
  }
}
