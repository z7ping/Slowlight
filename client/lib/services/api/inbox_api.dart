import '../../models/task.dart';
import '../data_mode_manager.dart';
import '../local_api_service.dart';

/// 收集箱相关 API
class InboxApi {
  static final _localApi = LocalApiService();

  /// 获取收集箱任务
  static Future<Map<String, dynamic>> getInbox() async {
    if (DataModeManager().isOffline) {
      return _localApi.getInbox();
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 快速添加到收集箱
  static Future<Task> quickAddToInbox(String title, {int? systemTagId}) async {
    if (DataModeManager().isOffline) {
      return _localApi.quickAddToInbox(title, systemTagId: systemTagId);
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 移动收集箱任务到其他清单
  static Future<Task> moveInboxTask(int taskId, int listId) async {
    if (DataModeManager().isOffline) {
      return _localApi.moveInboxTask(taskId, listId);
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }

  /// 获取收集箱任务数量
  static Future<int> getInboxCount() async {
    if (DataModeManager().isOffline) {
      return _localApi.getInboxCount();
    }
    throw UnimplementedError('Cloud API not implemented yet');
  }
}
