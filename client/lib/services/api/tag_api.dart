import '../../models/tag.dart';
import '../../models/task.dart';
import '../data_mode_manager.dart';
import '../local_api_service.dart';

/// 标签相关 API
class TagApi {
  static final _localApi = LocalApiService();

  /// 获取所有标签
  static Future<List<Tag>> getTags() async {
    if (DataModeManager().isOffline) {
      return _localApi.getTags();
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 创建标签
  static Future<Tag> createTag({required String name, required String color}) async {
    if (DataModeManager().isOffline) {
      return _localApi.createTag(name: name, color: color);
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 更新标签
  static Future<Tag> updateTag({required int id, String? name, String? color}) async {
    if (DataModeManager().isOffline) {
      return _localApi.updateTag(id: id, name: name, color: color);
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 删除标签
  static Future<void> deleteTag(int tagId) async {
    if (DataModeManager().isOffline) {
      return _localApi.deleteTag(tagId);
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 获取指定标签下的任务
  static Future<List<Task>> getTasksByTag(int tagId) async {
    if (DataModeManager().isOffline) {
      return _localApi.getTasksByTag(tagId);
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }
}
