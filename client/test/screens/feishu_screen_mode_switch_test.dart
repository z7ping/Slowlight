import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/repositories/feishu_integration_repository.dart';
import 'package:slowlight/screens/feishu_screen.dart';
import 'package:slowlight/services/data_mode_manager.dart';
import 'package:slowlight/ui/fx.dart';

import '../helpers/isolated_test_db.dart';
import '../support/fx_test_host.dart';

class _ModeSwitchRepository implements FeishuIntegrationRepository {
  final oldConfig = Completer<Map<String, dynamic>>();
  final oldTemplate = Completer<Map<String, dynamic>>();
  int configReads = 0;
  int templateCalls = 0;

  @override
  Future<Map<String, dynamic>> config() {
    ++configReads;
    if (configReads == 1) return oldConfig.future;
    return Future.value({
      'configured': true,
      'app_id': 'cloud_app',
      'table_url': 'https://cloud.example/base',
      'tables': {'任务': 'cloud-table'},
    });
  }

  @override
  Future<List<dynamic>> calendars() async => const [];

  @override
  Future<Map<String, dynamic>> createTemplate() {
    ++templateCalls;
    return oldTemplate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TemplateRepository implements FeishuIntegrationRepository {
  final pending = Completer<Map<String, dynamic>>();
  int configReads = 0;
  int templateCalls = 0;

  @override
  Future<Map<String, dynamic>> config() async {
    ++configReads;
    return {
      'configured': true,
      'app_id': configReads == 1 ? 'local_app' : 'cloud_app',
      'table_url': configReads == 1
          ? 'https://local.example/base'
          : 'https://cloud.example/base',
      'tables': const {},
    };
  }

  @override
  Future<List<dynamic>> calendars() async => const [];

  @override
  Future<Map<String, dynamic>> createTemplate() {
    ++templateCalls;
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await useIsolatedTestDb('feishu_screen_mode_switch');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataModeManager().setLocal();
  });

  testWidgets('P17 S16 旧本地配置迟到不能写进云端设置表单', (tester) async {
    final fake = _ModeSwitchRepository();
    await tester.pumpWidget(buildFxTestHost(
      home: FeishuScreen(repository: fake),
    ));
    await tester.pump();
    expect(fake.configReads, 1);

    await tester.runAsync(() => DataModeManager().setCloud());
    await tester.pump();
    await tester.pump();
    expect(fake.configReads, 2);

    fake.oldConfig.complete({
      'configured': true,
      'app_id': 'stale_local_app',
      'table_url': 'https://stale.example/base',
      'tables': {'任务': 'old-table'},
    });
    await tester.pump();
    final appId = tester.widget<FxInput>(find.byType(FxInput).first);
    expect(appId.controller!.text, 'cloud_app');
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P17 S16 模式切换后旧创建模板回执不能覆盖新模式配置',
      (tester) async {
    final fake = _TemplateRepository();
    await tester.pumpWidget(buildFxTestHost(
      home: FeishuScreen(repository: fake),
    ));
    await tester.pump();
    await tester.tap(find.text('创建数据模板'));
    await tester.pump();
    await tester.tap(find.text('创建模板'));
    await tester.pump();
    expect(fake.templateCalls, 1);

    await tester.runAsync(() => DataModeManager().setCloud());
    await tester.pump();
    await tester.pump();
    expect(fake.configReads, 2);

    fake.pending.complete({
      'bitable_url': 'https://stale.example/base',
      'tables': {'任务': 'stale-table'},
    });
    await tester.pump();
    final fields = tester.widgetList<FxInput>(find.byType(FxInput)).toList();
    expect(fields.first.controller!.text, 'cloud_app');
    expect(fields[2].controller!.text, 'https://cloud.example/base');
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
