import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/focus_home_screen.dart';
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
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    await tester.pump();
  }

  group('FocusHomeScreen 新导航', () {
    testWidgets('桌面端按主线、记录工具和组织工具分组', (tester) async {
      await pumpAt(tester, size: const Size(1200, 800));

      expect(find.byType(FocusHomeScreen), findsOneWidget);
      expect(find.text('今天'), findsWidgets);
      expect(find.text('回顾'), findsWidgets);
      expect(find.text('搜索'), findsOneWidget);
      expect(find.text('记录工具'), findsOneWidget);
      expect(find.text('任务'), findsOneWidget);
      expect(find.text('四象限'), findsOneWidget);
      expect(find.text('习惯'), findsOneWidget);
      expect(find.text('专注'), findsOneWidget);
      expect(find.text('日历'), findsOneWidget);
      expect(find.text('组织工具'), findsOneWidget);
      expect(find.text('本地数据'), findsOneWidget);
      expect(find.text('统计'), findsNothing);
      expect(find.text('时间分配'), findsNothing);
    });

    testWidgets('组织工具只展开低频组织入口', (tester) async {
      await pumpAt(tester, size: const Size(1200, 800));

      expect(find.text('清单'), findsNothing);
      expect(find.text('观察标签'), findsNothing);
      await tester.tap(find.text('组织工具'));
      await tester.pump();

      expect(find.text('清单'), findsOneWidget);
      expect(find.text('观察标签'), findsOneWidget);
    });

    testWidgets('四象限是一级记录工具并可直接进入', (tester) async {
      await pumpAt(tester, size: const Size(1200, 800));

      await tester.tap(find.text('四象限'));
      await tester.pump();

      expect(find.byType(QuadrantScreen), findsOneWidget);
    });

    testWidgets('回顾承载概览、统计和时间分配二级视图', (tester) async {
      await pumpAt(tester, size: const Size(1200, 800));

      await tester.tap(find.text('回顾').first);
      await tester.pump();

      expect(find.text('概览'), findsOneWidget);
      expect(find.text('统计'), findsOneWidget);
      expect(find.text('时间分配'), findsOneWidget);
    });

    testWidgets('移动端保留主线底栏和工具入口', (tester) async {
      await pumpAt(tester, size: const Size(500, 844));

      expect(find.text('今天'), findsWidgets);
      expect(find.text('回顾'), findsOneWidget);
      expect(find.byTooltip('工具'), findsOneWidget);
    });
  });
}
