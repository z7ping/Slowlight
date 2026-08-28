import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/reminder_screen.dart';
import 'package:slowlight/services/reminder_service.dart';
import 'package:slowlight/ui/theme_manager.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget buildHost(Widget home) {
  return ShadTheme(
    data: ThemeManager.shadLight,
    child: MaterialApp(
      theme: ThemeManager.lightTheme,
      home: home,
    ),
  );
}

void main() {
  group('ReminderScreen', () {
    group('初始状态', () {
      testWidgets('渲染不崩溃', (tester) async {
        await tester.pumpWidget(buildHost(const ReminderScreen()));
        await tester.pump();
        expect(find.byType(ReminderScreen), findsOneWidget);
      });

      testWidgets('Scaffold 存在', (tester) async {
        await tester.pumpWidget(buildHost(const ReminderScreen()));
        await tester.pump();
        expect(find.byType(Scaffold), findsOneWidget);
      });

      testWidgets('页面标题存在', (tester) async {
        await tester.pumpWidget(buildHost(const ReminderScreen()));
        await tester.pump();
        expect(find.text('休息提醒'), findsOneWidget);
      });

      testWidgets('今日统计展示清晰指标和节奏说明', (tester) async {
        await tester.pumpWidget(buildHost(const ReminderScreen()));
        await tester.pump();

        expect(find.text('今日统计'), findsOneWidget);
        expect(find.text('工作'), findsOneWidget);
        expect(find.text('休息'), findsOneWidget);
        expect(find.text('跳过率'), findsOneWidget);
        expect(find.text('连续不跳过'), findsOneWidget);
        expect(find.textContaining('每轮工作'), findsOneWidget);
      });
    });

    group('多次 pump', () {
      testWidgets('不崩溃', (tester) async {
        await tester.pumpWidget(buildHost(const ReminderScreen()));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(ReminderScreen), findsOneWidget);
      });
    });

    group('工作中操作', () {
      testWidgets('不显示暂停和停止按钮', (tester) async {
        await tester.pumpWidget(buildHost(const ReminderScreen()));
        await tester.pump();

        await tester.tap(find.text('开始工作'));
        await tester.pump();

        expect(find.text('开始小憩'), findsOneWidget);
        expect(find.text('暂停'), findsNothing);
        expect(find.text('停止'), findsNothing);

        ReminderService().stopAll();
        await tester.pump();
      });
    });

    group('桌面端布局', () {
      testWidgets('宽屏 > 800px 渲染不崩溃', (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(buildHost(const ReminderScreen()));
        await tester.pump();
        expect(find.byType(ReminderScreen), findsOneWidget);
      });

      testWidgets('窄屏渲染不崩溃', (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(buildHost(const ReminderScreen()));
        await tester.pump();
        expect(find.byType(ReminderScreen), findsOneWidget);
      });
    });

    group('dispose 安全', () {
      testWidgets('快速销毁不崩溃', (tester) async {
        await tester.pumpWidget(buildHost(const ReminderScreen()));
        await tester.pump();
        await tester.pumpWidget(buildHost(const Scaffold()));
        await tester.pump();
        expect(find.byType(ReminderScreen), findsNothing);
      });
    });
  });
}
