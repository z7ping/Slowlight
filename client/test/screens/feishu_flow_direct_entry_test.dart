import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/repositories/feishu_integration_repository.dart';
import 'package:slowlight/screens/feishu_screen.dart';
import 'package:slowlight/screens/integration_screen.dart';
import 'package:slowlight/screens/settings_screen.dart';
import 'package:slowlight/services/data_mode_manager.dart';
import 'package:slowlight/ui/fx.dart';

import '../helpers/isolated_test_db.dart';
import '../support/fx_test_host.dart';

class _UnmappedFeishuRepository implements FeishuIntegrationRepository {
  int templateCalls = 0;
  int syncAllCalls = 0;

  @override
  Future<Map<String, dynamic>> config() async => {
        'configured': true,
        'app_id': 'cli_demo',
        'table_url': '',
        'tables': const <String, dynamic>{},
      };

  @override
  Future<Map<String, dynamic>> createTemplate() async {
    templateCalls++;
    return {
      'bitable_url': 'https://feishu.cn/base/demo',
      'tables': {
        '任务表': 'task',
        '番茄钟表': 'focus',
        '休息提醒表': 'rest',
        '标签表': 'tags',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> syncAll() async {
    syncAllCalls++;
    return {'results': {'任务表': 2}, 'errors': <String>[]};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await useIsolatedTestDb('feishu_flow_direct_entry');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'user_data': 'invalid-data'});
    await DataModeManager().setLocal();
  });

  testWidgets('Android 连接与同步直接进入飞书，没有平台集成中转页', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.reset();
    });

    await tester.pumpWidget(buildFxTestHost(
      home: const SettingsScreen(initialSection: 'sync'),
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('settings.sync.feishu')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings.sync.feishu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(FeishuScreen), findsOneWidget);
    expect(find.byType(IntegrationScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('仅保存飞书凭据时禁止同步，创建模板回填后开放同步', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = _UnmappedFeishuRepository();

    await tester.pumpWidget(buildFxTestHost(
      home: FeishuScreen(repository: fake),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    FxButton syncAll() =>
        tester.widget<FxButton>(find.widgetWithText(FxButton, '同步全部'));

    expect(syncAll().onPressed, isNull);
    expect(find.textContaining('凭据已保存'), findsWidgets);
    expect(find.byType(FxInput), findsNothing);

    await tester.ensureVisible(find.text('创建数据模板'));
    await tester.tap(find.text('创建数据模板'));
    await tester.pump();
    await tester.tap(find.text('创建模板'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(fake.templateCalls, 1);
    expect(syncAll().onPressed, isNotNull);
    expect(find.textContaining('已识别'), findsWidgets);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
