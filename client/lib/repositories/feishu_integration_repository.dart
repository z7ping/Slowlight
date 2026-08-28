import '../services/api_service.dart';
import '../services/data_mode_manager.dart';
import '../services/local_feishu_config_store.dart';
import '../services/local_feishu_integration_service.dart';

/// 飞书集成边界：页面不直接依赖 HTTP，由数据模式决定本机或云端实现。
class FeishuIntegrationRepository {
  factory FeishuIntegrationRepository() => _instance;
  FeishuIntegrationRepository._();
  static final _instance = FeishuIntegrationRepository._();

  bool get _local => DataModeManager().isLocal;
  Future<Map<String, dynamic>> config() =>
      _local ? LocalFeishuConfigStore().load() : ApiService.getFeishuConfig();
  Future<void> save(
      {required String appId,
      required String appSecret,
      String? tableUrl}) async {
    if (_local)
      return LocalFeishuConfigStore()
          .save(appId: appId, appSecret: appSecret, tableUrl: tableUrl);
    await ApiService.saveIntegrationConfig(
        platform: 'feishu',
        appId: appId,
        appSecret: appSecret,
        tableUrl: tableUrl);
  }

  Future<Map<String, dynamic>> syncTasks() => _local
      ? LocalFeishuIntegrationService().syncTasks()
      : ApiService.syncToFeishu();
  Future<List<dynamic>> calendars() => _local
      ? Future.value(const [])
      : ApiService.getIntegrationCalendars('feishu');
  Future<Map<String, dynamic>> syncAll() => _local
      ? LocalFeishuIntegrationService().syncAll()
      : ApiService.syncAllIntegration('feishu');
  Future<Map<String, dynamic>> syncSessions() => _local
      ? LocalFeishuIntegrationService().syncSessions()
      : ApiService.syncSessionsToFeishu();
  Future<Map<String, dynamic>> syncTags() => _local
      ? LocalFeishuIntegrationService().syncTags()
      : ApiService.syncTagsToFeishu();
  Future<Map<String, dynamic>> createTemplate() => _local
      ? LocalFeishuIntegrationService().createTemplate()
      : ApiService.createFeishuTemplate();
  Future<Map<String, dynamic>> connect(String url) => _local
      ? LocalFeishuIntegrationService().connect(url)
      : ApiService.connectExistingFeishu(url);
  Future<Map<String, dynamic>> importData() => _local
      ? Future.error(StateError('本机模式当前仅支持单向导出，飞书导入不经过云端服务'))
      : ApiService.importFromFeishu();
  Future<Map<String, dynamic>> syncReminders() => _local
      ? LocalFeishuIntegrationService().syncReminders()
      : ApiService.syncRemindersToFeishu();
  Future<Map<String, dynamic>> syncCalendar(String id) => _local
      ? Future.error(StateError('本机飞书不使用服务端日历同步'))
      : ApiService.syncToCalendar('feishu', id);
}
