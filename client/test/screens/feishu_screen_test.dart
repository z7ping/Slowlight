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
