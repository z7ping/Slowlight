import '../models/todo_list.dart';
import '../services/cloud_api_service.dart';
import '../services/data_mode_manager.dart';
import '../services/data_source.dart';
import '../services/local_api_service.dart';

/// 清单 Repository，封装清单相关数据源切换逻辑
///
/// 通过 [ApiDataSource] 抽象层访问数据，自动适配本地模式（SQLite）
/// 和云端模式（Go 后端）。调用者无需关心底层数据源的实现细节。
///
/// ```dart
/// // 使用默认数据源（根据 DataModeManager 自动切换）
/// final repo = ListRepository();
///
/// // 显式指定数据源（用于测试或特殊场景）
/// final repo = ListRepository(dataSource: mockDataSource);
/// ```
class ListRepository {
  final ApiDataSource? _fixedDataSource;

  ListRepository({ApiDataSource? dataSource})
      : _fixedDataSource = dataSource;

  /// 动态选择数据源：固定源 > 按当前模式
  ApiDataSource get _dataSource => _fixedDataSource ?? (
    DataModeManager().isLocal ? LocalApiService() : CloudApiService()
  );

  // ===== 清单查询 =====

  /// 获取所有清单
  Future<List<TodoList>> getLists() => _dataSource.getLists();

  // ===== 清单操作 =====

  /// 创建清单
  Future<TodoList> createList({
    required String name,
    String icon = '📁',
    String color = '#1890ff',
    bool isInbox = false,
  }) => _dataSource.createList(name: name, icon: icon, color: color, isInbox: isInbox);

  /// 更新清单
  Future<TodoList> updateList({
    required int id,
    String? name,
    String? icon,
    String? color,
  }) => _dataSource.updateList(id: id, name: name, icon: icon, color: color);

  /// 删除清单
  Future<void> deleteList(int id) => _dataSource.deleteList(id);
}
