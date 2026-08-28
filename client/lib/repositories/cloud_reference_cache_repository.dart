import '../db/cloud_cache_db.dart';
import '../models/observation_tag.dart';
import '../models/tag.dart';

/// Cloud Cache 中相对稳定的引用数据读取边界。
///
/// 当前只提供只读 fallback；Tag / ObservationTag 的编辑仍保持在线，
/// 避免在没有完整编辑冲突语义前扩大离线写入范围。
class CloudReferenceCacheRepository {
  final CloudCacheDb _cache = CloudCacheDb();

  Future<List<Tag>> getTags() async {
    final db = await _cache.database;
    final rows = await db.query('tags', orderBy: 'created_at ASC');
    return rows.map((row) {
      final localId = row['id'] as int;
      final serverId = row['server_id'] as int?;
      return Tag(
        id: serverId ?? -localId,
        name: row['name'] as String? ?? '',
        color: row['color'] as String? ?? '#0075de',
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    }).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getSystemTagMaps() async {
    final db = await _cache.database;
    final rows = await db.query('system_tags', orderBy: 'created_at ASC');
    return rows.map((row) {
      final localId = row['id'] as int;
      final serverId = row['server_id'] as int?;
      return <String, dynamic>{
        'id': serverId ?? -localId,
        'name': row['name'] as String? ?? '',
        'icon': row['icon'] as String? ?? '🏷️',
        'color': row['color'] as String? ?? '#1890ff',
        'dimension_key': row['dimension_key'] as String? ?? '',
        'is_default': (row['is_default'] as int? ?? 0) == 1,
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
      };
    }).toList(growable: false);
  }

  Future<List<ObservationTag>> getObservationTags() async {
    final values = await getSystemTagMaps();
    return values.map(ObservationTag.fromJson).toList(growable: false);
  }
}
