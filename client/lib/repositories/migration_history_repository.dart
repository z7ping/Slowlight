import '../services/api_service.dart';
import '../services/data_mode_manager.dart';
import '../services/local_migration_report_store.dart';

/// 迁移历史的数据边界：本机模式只读 SQLite；云端模式可分别读取本机和服务端审计。
class MigrationHistoryRepository {
  Future<Map<String, dynamic>?> latest() async {
    if (DataModeManager().isLocal) {
      final reports = await LocalMigrationReportStore().all();
      return reports.isEmpty ? null : reports.first;
    }
    return ApiService.getLatestMigrationReport();
  }

  Future<List<Map<String, dynamic>>> local() =>
      LocalMigrationReportStore().all();

  Future<List<Map<String, dynamic>>> cloud() async =>
      (await ApiService.getMigrationReports())
          .map((item) => {
                ...item,
                'source': 'cloud',
                'status': item['status'] ?? 'succeeded'
              })
          .toList();

  Future<List<Map<String, dynamic>>> all() =>
      DataModeManager().isLocal ? local() : cloud();
}
