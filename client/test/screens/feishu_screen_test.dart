import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/screens/feishu_screen.dart';
import 'package:slowlight/services/data_mode_manager.dart';

import '../helpers/isolated_test_db.dart';
import '../support/fx_test_host.dart';

void main() {
  group('FeishuScreen 稳定性', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues(const {});
      await useIsolatedTestDb('feishu_screen');
    });
    setUp(() async => DataModeManager().setLocal());

    testWidgets('本地配置读取完成后不产生运行异常', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const FeishuScreen()));
      await tester.pump(const Duration(seconds: 3));

      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    for (final width in [320.0, 360.0, 393.0]) {
      testWidgets('飞书概况 ${width}dp + 130% 字体自适应不溢出', (tester) async {
        tester.view.physicalSize = Size(width, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(buildFxTestHost(
          home: const FeishuScreen(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
        ));
        await tester.pump(const Duration(seconds: 3));
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }


    for (final width in [1024.0, 1280.0]) {
      testWidgets('飞书双栏 ${width}dp 连接配置与数据同步首卡顶边对齐',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(buildFxTestHost(
          home: const FeishuScreen(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
        ));
        await tester.pump(const Duration(seconds: 3));
        final config = find.byKey(
          const ValueKey('feishu.config.primaryCard'),
        );
        final sync = find.byKey(
          const ValueKey('feishu.sync.primaryCard'),
        );
        expect(config, findsOneWidget);
        expect(sync, findsOneWidget);
        expect(
          (tester.getTopLeft(config).dy - tester.getTopLeft(sync).dy).abs(),
          lessThan(1),
        );
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }

    testWidgets('窄屏不产生布局溢出', (tester) async {
      tester.view.physicalSize = const Size(420, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildFxTestHost(home: const FeishuScreen()));
      await tester.pump(const Duration(seconds: 3));

      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  });
}
