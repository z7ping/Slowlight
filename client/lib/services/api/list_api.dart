import '../../models/todo_list.dart';
import '../data_mode_manager.dart';
import '../local_api_service.dart';

/// 清单相关 API
class ListApi {
  static final _localApi = LocalApiService();

  /// 获取所有清单
  static Future<List<TodoList>> getLists() async {
    if (DataModeManager().isOffline) {
      return _localApi.getLists();
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 创建清单
  static Future<TodoList> createList({
    required String name,
    String icon = '📁',
    String color = '#1890ff',
  }) async {
    if (DataModeManager().isOffline) {
      return _localApi.createList(name: name, icon: icon, color: color);
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 更新清单
  static Future<TodoList> updateList({
    required int id,
    String? name,
    String? icon,
    String? color,
  }) async {
    if (DataModeManager().isOffline) {
      return _localApi.updateList(id: id, name: name, icon: icon, color: color);
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 删除清单
  static Future<void> deleteList(int id) async {
    if (DataModeManager().isOffline) {
      return _localApi.deleteList(id);
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }
}
