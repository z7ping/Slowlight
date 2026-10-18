import '../models/dimension.dart';
import '../models/observation_tag.dart';
import '../repositories/observation_tag_repository.dart';

/// 任务沿用 system_tag_id -> 观察标签 -> 四维度的正式数据链路。
///
/// 只在用户主动选择维度并保存时解析或创建对应的默认观察标签，避免
/// 为任务另造 dimension_key 字段或将普通清单当成四维坐标。
class TaskDimensionAssignment {
  final ObservationTagRepository _tags;

  TaskDimensionAssignment({ObservationTagRepository? repository})
      : _tags = repository ?? ObservationTagRepository();

  Future<String?> dimensionOf(int? systemTagId) async {
    if (systemTagId == null) return null;
    final tags = await _tags.getAll();
    for (final tag in tags) {
      if (tag.id == systemTagId) return tag.dimensionKey;
    }
    return null;
  }

  /// 未主动调整时，应保留调用入口传来的原观察标签。
  Future<int?> resolve({
    required String? dimensionKey,
    int? originalTagId,
    bool changed = true,
  }) async {
    if (!changed) return originalTagId;
    if (dimensionKey == null || dimensionKey.isEmpty) return null;
    final definition = DimensionCatalog.byKey(dimensionKey);
    if (definition == null) throw ArgumentError('无效的归属维度');

    final tags = await _tags.getAll();
    final reusable = _defaultTag(tags, dimensionKey, definition.name);
    if (reusable != null) return reusable.id;

    // 新用户不一定有历史四维标签：按需建立对应的默认观察标签。
    // 不复用任意同维度自定义标签，避免把「分心」等具体观察误赋予任务。
    try {
      final created = await _tags.create(
        name: definition.name,
        icon: definition.icon,
        color: definition.color,
        dimensionKey: definition.keyValue,
      );
      return created.id;
    } catch (_) {
      // 多设备并发创建时，重新读取并复用已存在的标签。
      final refreshed = await _tags.getAll();
      final existing = _defaultTag(refreshed, dimensionKey, definition.name);
      if (existing != null) return existing.id;
      rethrow;
    }
  }

  ObservationTag? _defaultTag(
    List<ObservationTag> tags,
    String key,
    String name,
  ) {
    for (final tag in tags) {
      if (tag.dimensionKey == key && tag.isDefault) return tag;
    }
    for (final tag in tags) {
      if (tag.dimensionKey == key && tag.name == name) return tag;
    }
    return null;
  }
}
