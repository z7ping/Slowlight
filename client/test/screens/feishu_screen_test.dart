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
  group('FeishuScreen', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues(const {});
      await useIsolatedTestDb('feishu_screen');
    });
    setUp(() async => DataModeManager().setLocal());

    testWidgets('使用统一页头并保持稳定', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pump();

      expect(find.byType(FeishuScreen), findsOneWidget);
      expect(find.text('飞书集成'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('配置读取完成后展示连接与同步层级', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('飞书多维表格'), findsOneWidget);
      expect(find.text('连接配置'), findsOneWidget);
      expect(find.text('数据同步'), findsOneWidget);
      expect(find.text('创建标准的 8 张数据表'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('窄屏保持单列且无布局溢出', (tester) async {
      tester.view.physicalSize = const Size(420, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app());
      await tester.pump(const Duration(seconds: 3));

      expect(find.byType(FeishuScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
