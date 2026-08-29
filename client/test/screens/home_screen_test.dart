import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/home_screen.dart';
import 'package:slowlight/screens/quadrant_screen.dart';
import 'package:slowlight/ui/theme_manager.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  Widget buildApp() {
    return ShadTheme(
      data: ThemeManager.shadLight,
      child: MaterialApp(
        theme: ThemeManager.lightTheme,
        home: const HomeScreen(),
      ),
    );
  }

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
    await tester.pumpWidget(buildApp());
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
      });
    }

    testWidgets('360×800 在 130% 系统字体下不产生布局异常', (tester) async {
      await pumpAt(
        tester,
        size: const Size(360, 800),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('四象限入口可以进入实际功能页', (tester) async {
      await pumpAt(tester, size: const Size(1200, 800));

      await tester.tap(find.text('四象限'));
      await tester.pump();

      expect(find.byType(QuadrantScreen), findsOneWidget);
    });

    testWidgets('移动端支持左缘右滑打开并左滑关闭抽屉', (tester) async {
      await pumpAt(tester, size: const Size(360, 800));

      // 避开 Android 系统返回手势占用的最外侧区域，从应用内近边缘滑动。
      await tester.dragFrom(const Offset(40, 240), const Offset(280, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭'), findsOneWidget);

      await tester.dragFrom(const Offset(260, 240), const Offset(-280, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭'), findsNothing);
    });

    testWidgets('移动端点击抽屉遮罩可以关闭', (tester) async {
      await pumpAt(tester, size: const Size(360, 800));

      await tester.tap(find.byTooltip('工具'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭'), findsOneWidget);

      await tester.tapAt(const Offset(350, 300));
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭'), findsNothing);
    });

    testWidgets('Android 返回键先关闭工具页', (tester) async {
      await pumpAt(tester, size: const Size(360, 800));
      await tester.tap(find.byTooltip('工具'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('四象限'));
      await tester.pumpAndSettle();
      expect(find.byType(QuadrantScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(QuadrantScreen), findsNothing);
      expect(find.text('再按一次退出 Slowlight'), findsNothing);
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
    });
  });
}
