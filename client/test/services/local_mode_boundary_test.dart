import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('飞书页面只通过数据模式仓库访问集成能力', () {
    final source = File('lib/screens/feishu_screen.dart').readAsStringSync();
    expect(source, isNot(contains("services/api_service.dart")));
    expect(source, contains('FeishuIntegrationRepository'));

    final repository =
        File('lib/repositories/feishu_integration_repository.dart')
            .readAsStringSync();
    expect(repository, contains('LocalFeishuIntegrationService().syncAll()'));
    expect(repository,
        contains('LocalFeishuIntegrationService().createTemplate()'));
    expect(
        repository, contains('LocalFeishuIntegrationService().connect(url)'));
  });

  test('迁移历史在本机模式读取 SQLite 留痕而非服务端审计', () {
    final source = File('lib/repositories/migration_history_repository.dart')
        .readAsStringSync();
    expect(source, contains('DataModeManager().isLocal'));
    expect(source, contains('LocalMigrationReportStore().all()'));
  });

  test('迁移历史把本机失败快照和云端审计分开处理', () {
    final store = File('lib/services/local_migration_report_store.dart')
        .readAsStringSync();
    final dialog =
        File('lib/screens/migration_history_dialog.dart').readAsStringSync();
    expect(store, contains("'status': 'failed'"));
    expect(store, contains('retrySnapshot'));
    expect(dialog, contains('云端审计'));
    expect(dialog, contains('本机记录'));
    expect(dialog, contains("status == 'failed'"));
  });
}
