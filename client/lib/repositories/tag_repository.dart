import '../models/tag.dart';
import '../models/task.dart';
import '../services/cloud_api_service.dart';
import '../services/data_mode_manager.dart';
import '../services/data_source.dart';
import '../services/local_api_service.dart';

/// 标签 Repository，封装标签相关数据源切换逻辑
///
/// 通过 [ApiDataSource] 抽象层访问数据，自动适配本地模式（SQLite）
/// 和云端模式（Go 后端）。调用者无需关心底层数据源的实现细节。
///
/// ```dart
/// // 使用默认数据源（根据 DataModeManager 自动切换）
/// final repo = TagRepository();
///
/// // 显式指定数据源（用于测试或特殊场景）
/// final repo = TagRepository(dataSource: mockDataSource);
/// ```
class TagRepository {
  final ApiDataSource? _fixedDataSource;

  TagRepository({ApiDataSource? dataSource})
      : _fixedDataSource = dataSource;

  /// 动态选择数据源：固定源 > 按当前模式
  ApiDataSource get _dataSource => _fixedDataSource ?? (
    DataModeManager().isLocal ? LocalApiService() : CloudApiService()
  );

  // ===== 标签查询 =====

  /// 获取所有标签
  Future<List<Tag>> getTags() => _dataSource.getTags();

  /// 获取指定标签下的任务
  Future<List<Task>> getTasksByTag(int tagId) => _dataSource.getTasksByTag(tagId);

  // ===== 标签操作 =====

  /// 创建标签
  Future<Tag> createTag({required String name, required String color}) =>
      _dataSource.createTag(name: name, color: color);

  /// 更新标签
  Future<Tag> updateTag({required int id, String? name, String? color}) =>
      _dataSource.updateTag(id: id, name: name, color: color);

  /// 删除标签
  Future<void> deleteTag(int tagId) => _dataSource.deleteTag(tagId);
}
