import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:slowlight/services/data_mode_manager.dart';
import 'package:slowlight/screens/home_screen.dart';
import 'package:slowlight/screens/quadrant_screen.dart';
import 'package:slowlight/screens/task_create_sheet.dart';

import '../support/fx_test_host.dart';
import '../helpers/isolated_test_db.dart';

void main() {
  setUpAll(() async {
    await useIsolatedTestDb('home_screen');
    SharedPreferences.setMockInitialValues({'data_mode': 'local'});
    FlutterSecureStorage.setMockInitialValues({});
    await DataModeManager().setLocal();
  });
  Future<void> pumpAt(
    WidgetTester tester, {
    required Size size,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(buildFxTestHost(home: const HomeScreen()));
    await tester.pump();
  }

  group('HomeScreen 稳定契约', () {
    for (final size in [
      const Size(360, 800),
      const Size(412, 915),
      const Size(500, 844),
      const Size(1200, 800),
    ]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()} 主壳不产生布局异常',
          (tester) async {
        await pumpAt(tester, size: size);
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }

    testWidgets('移动端只保留悬浮快速添加任务主入口', (tester) async {
      await pumpAt(tester, size: const Size(360, 800));
      expect(fxTooltipFinder('快速添加任务（按住可拖动）'), findsOneWidget);
      expect(fxTooltipFinder('添加任务'), findsNothing);
      expect(fxTooltipFinder('记录观察'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('悬浮添加任务按钮移动后仍可再次拖动并点击', (tester) async {
      await pumpAt(tester, size: const Size(360, 800));
      final fab = fxTooltipFinder('快速添加任务（按住可拖动）');

      final initial = tester.getCenter(fab);
      await tester.drag(fab, const Offset(-124, -145));
      await tester.pump();
      final moved = tester.getCenter(fab);
      expect(moved.dx, lessThan(initial.dx - 90));
      expect(moved.dy, lessThan(initial.dy - 110));

      // 从新的位置继续拖动，而不是仍依赖 Scaffold FAB 的原始命中区域。
      await tester.drag(fab, const Offset(38, -35));
      await tester.pump();
      final movedAgain = tester.getCenter(fab);
      expect(movedAgain.dx, greaterThan(moved.dx + 15));
      expect(movedAgain.dy, lessThan(moved.dy - 15));

      // 新坐标上的真实点击必须仍打开原有任务创建 Sheet。
      await tester.tap(fab);
      await tester.pump();
      expect(find.byType(TaskCreateSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('悬浮按钮拖到边界后仍可点按', (tester) async {
      await pumpAt(tester, size: const Size(360, 800));
      final fab = fxTooltipFinder('快速添加任务（按住可拖动）');
      await tester.drag(fab, const Offset(-900, -900));
      await tester.pump();

      final rect = tester.getRect(fab);
      expect(rect.left, greaterThanOrEqualTo(0));
      // FAB 必须保持在 Scaffold body 内，而不是移入 AppBar / 底部导航。
      expect(rect.top, greaterThanOrEqualTo(48));
      await tester.tap(fab);
      await tester.pump();
      expect(find.byType(TaskCreateSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('360×800 在 130% 系统字体下不产生布局异常', (tester) async {
      await pumpAt(
        tester,
        size: const Size(360, 800),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('四象限入口可以进入实际功能页', (tester) async {
      await pumpAt(tester, size: const Size(1200, 800));

      await tester.tap(find.text('四象限'));
      await tester.pump();

      expect(find.byType(QuadrantScreen), findsOneWidget);
      await disposeFxTestHost(tester);
    });

    testWidgets('移动端支持左缘右滑打开并左滑关闭抽屉', (tester) async {
      await pumpAt(tester, size: const Size(360, 800));

      // 避开 Android 系统返回手势占用的最外侧区域，从应用内近边缘滑动。
      await tester.dragFrom(const Offset(40, 240), const Offset(280, 0));
      await tester.pumpAndSettle();
      expect(fxTooltipFinder('关闭'), findsOneWidget);

      await tester.dragFrom(const Offset(260, 240), const Offset(-280, 0));
      await tester.pumpAndSettle();
      expect(fxTooltipFinder('关闭'), findsNothing);
      await disposeFxTestHost(tester);
    });

    testWidgets('移动端点击抽屉遮罩可以关闭', (tester) async {
      await pumpAt(tester, size: const Size(360, 800));

      await tester.tap(fxTooltipFinder('工具'));
      await tester.pumpAndSettle();
      expect(fxTooltipFinder('关闭'), findsOneWidget);

      await tester.tapAt(const Offset(350, 300));
      await tester.pumpAndSettle();
      expect(fxTooltipFinder('关闭'), findsNothing);
      await disposeFxTestHost(tester);
    });

    testWidgets('Android 返回键先关闭工具页', (tester) async {
      await pumpAt(tester, size: const Size(360, 800));
      await tester.tap(fxTooltipFinder('工具'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('四象限'));
      await tester.pumpAndSettle();
      expect(find.byType(QuadrantScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(QuadrantScreen), findsNothing);
      expect(find.text('再按一次退出 Slowlight'), findsNothing);
      await disposeFxTestHost(tester);
    });

    testWidgets('Android 首页需要两次返回才退出', (tester) async {
      var exitCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') exitCalls++;
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      await pumpAt(tester, size: const Size(360, 800));

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('再按一次退出 Slowlight'), findsOneWidget);
      expect(exitCalls, 0);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exitCalls, 1);
      await disposeFxTestHost(tester);
    });
  });
}
