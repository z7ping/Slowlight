import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/ai/ai_models.dart';
import 'package:slowlight/screens/settings_screen.dart';
import 'package:slowlight/services/data_mode_manager.dart';
import 'package:slowlight/services/sync_service.dart';

import '../helpers/isolated_test_db.dart';
import '../support/fx_test_host.dart';

void main() {
  setUpAll(() async {
    await useIsolatedTestDb('settings_p17_verification');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'user_data': 'invalid-data'});
    FlutterSecureStorage.setMockInitialValues({});
    DataModeManager().resetForTesting();
    await DataModeManager().setCloud();
  });

  void desktop(WidgetTester tester) {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('P17 S13 初次核对失败不冒充无冲突，重试后才显示确认数量',
      (tester) async {
    desktop(tester);
    var reads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: SettingsScreen(
        initialSection: 'sync',
        conflictLoader: () async {
          if (++reads == 1) throw StateError('cloud unavailable');
          return [
            ConflictInfo(
              local: {'id': 1},
              remote: {'id': 1},
              table: 'tasks',
              recordId: 1,
            ),
          ];
        },
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(reads, 1);
    expect(find.text('冲突状态未确认，请重新检查'), findsOneWidget);
    expect(find.text('无待处理冲突'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('settings.sync.recheck_conflicts')),
    );
    await tester.pump();
    await tester.pump();
    expect(reads, 2);
    expect(find.text('1 条记录需要选择保留版本'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings.sync.recheck_conflicts')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P17 S13 旧账号/模式的迟到冲突结果不能覆盖较新查询',
      (tester) async {
    desktop(tester);
    final stale = Completer<List<ConflictInfo>>();
    var reads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: SettingsScreen(
        initialSection: 'sync',
        conflictLoader: () {
          if (++reads == 1) return stale.future;
          return Future.value([
            ConflictInfo(local: 1, remote: 2, table: 'tasks', recordId: 1),
            ConflictInfo(local: 3, remote: 4, table: 'tasks', recordId: 2),
          ]);
        },
      ),
    ));
    await tester.pump();
    expect(reads, 1);
    expect(find.text('正在核对同步冲突…'), findsOneWidget);

    await tester.runAsync(() => DataModeManager().setLocal());
    await tester.pump();
    await tester.runAsync(() => DataModeManager().setCloud());
    await tester.pump();
    await tester.pump();
    expect(reads, 2);
    expect(find.text('2 条记录需要选择保留版本'), findsOneWidget);

    stale.complete([]);
    await tester.pump();
    expect(find.text('2 条记录需要选择保留版本'), findsOneWidget);
    expect(find.text('无待处理冲突'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P17 S03 AI 源错误可重试，只有重新读取成功才更新摘要',
      (tester) async {
    desktop(tester);
    var reads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: SettingsScreen(
        initialSection: 'ai',
        aiConfigLoader: () async {
          if (++reads == 1) throw StateError('ai config unavailable');
          return const AiConfig(enabled: true, provider: AiProviderType.openai);
        },
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('读取 AI 配置失败'), findsOneWidget);
    expect(find.textContaining('当前服务商：OpenAI'), findsNothing);

    await tester.tap(find.text('重试读取'));
    await tester.pump();
    await tester.pump();
    expect(reads, 2);
    expect(find.textContaining('当前服务商：OpenAI'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
