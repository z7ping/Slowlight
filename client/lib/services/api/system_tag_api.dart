import '../data_mode_manager.dart';
import '../local_api_service.dart';

/// 系统标签相关 API
class SystemTagApi {
  static final _localApi = LocalApiService();

  /// 获取系统标签列表
  static Future<List<Map<String, dynamic>>> getSystemTags() async {
    if (DataModeManager().isOffline) {
      return _localApi.getSystemTags();
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 创建系统标签
  static Future<Map<String, dynamic>> createSystemTag({
    required String name,
    required String icon,
    required String color,
  }) async {
    if (DataModeManager().isOffline) {
      return _localApi.createSystemTag(name: name, icon: icon, color: color);
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 更新系统标签
  static Future<Map<String, dynamic>> updateSystemTag(
    int id, {
    String? name,
    String? icon,
    String? color,
  }) async {
    if (DataModeManager().isOffline) {
      return _localApi.updateSystemTag(id, icon: icon, color: color);
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 删除系统标签
  static Future<void> deleteSystemTag(int id) async {
    if (DataModeManager().isOffline) {
      return _localApi.deleteSystemTag(id);
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }
}
