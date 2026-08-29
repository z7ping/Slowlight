import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/screens/feishu_screen.dart';
import 'package:slowlight/services/data_mode_manager.dart';
import 'package:slowlight/ui/theme_manager.dart';

import '../helpers/isolated_test_db.dart';

Widget _app() => ShadTheme(
      data: ThemeManager.shadLight,
      child: const MaterialApp(home: FeishuScreen()),
    );

void main() {
  group('FeishuScreen 稳定性', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues(const {});
      await useIsolatedTestDb('feishu_screen');
    });
    setUp(() async => DataModeManager().setLocal());

    testWidgets('本地配置读取完成后不产生运行异常', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pump(const Duration(seconds: 3));

      expect(tester.takeException(), isNull);
    });

    testWidgets('窄屏不产生布局溢出', (tester) async {
      tester.view.physicalSize = const Size(420, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app());
      await tester.pump(const Duration(seconds: 3));

      expect(tester.takeException(), isNull);
    });
  });
}
