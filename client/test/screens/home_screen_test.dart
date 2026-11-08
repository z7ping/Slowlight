import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:slowlight/services/data_mode_manager.dart';
import 'package:slowlight/services/data_service.dart';
import 'package:slowlight/screens/habit_tool_screen.dart';
import 'package:slowlight/screens/task_tool_screen.dart';
import 'package:slowlight/screens/list_manage_screen.dart';
import 'package:slowlight/screens/about_screen.dart';
import 'package:slowlight/widgets/task_detail_sheet.dart';
import 'package:slowlight/ui/fx.dart' show FxInkWell, FxGestureDetector;
import 'package:slowlight/screens/home_screen.dart';
import 'package:slowlight/screens/quadrant_screen.dart';
import 'package:slowlight/screens/task_create_sheet.dart';
import 'package:slowlight/widgets/dashboard/dashboard_body.dart';

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

    testWidgets('X14 Android 底部导航还原原型：透明选中项、等宽与状态切换',
        (tester) async {
      await pumpAt(tester, size: const Size(360, 800));

      final bar = find.byKey(const ValueKey('home.bottom-nav'));
      final todayItem = find.byKey(const ValueKey('home.bottom-nav.today'));
      final reviewItem = find.byKey(const ValueKey('home.bottom-nav.review'));
      expect(bar, findsOneWidget);
      expect(todayItem, findsOneWidget);
      expect(reviewItem, findsOneWidget);

      // 原型只有图标与文字变色；选中项不能再绘制整块强调色背景。
      expect(tester.widget<FxInkWell>(todayItem).child, isA<ConstrainedBox>());
      expect(tester.widget<FxInkWell>(reviewItem).child, isA<ConstrainedBox>());
      expect(tester.getSize(todayItem).width,
          closeTo(tester.getSize(reviewItem).width, 0.01));
      expect(tester.getSize(todayItem).height, greaterThanOrEqualTo(58));

      final todayIcon = tester.widget<Icon>(find.descendant(
        of: todayItem,
        matching: find.byType(Icon),
      ));
      final reviewIcon = tester.widget<Icon>(find.descendant(
        of: reviewItem,
        matching: find.byType(Icon),
      ));
      expect(todayIcon.size, 17);
      expect(reviewIcon.size, 17);
      expect(todayIcon.color, isNot(reviewIcon.color));

      await tester.tap(reviewItem);
      await tester.pump();
      expect(find.byKey(const ValueKey('home.bottom-nav')), findsOneWidget);
      final selectedReviewIcon = tester.widget<Icon>(find.descendant(
        of: reviewItem,
        matching: find.byType(Icon),
      ));
      expect(selectedReviewIcon.color, todayIcon.color);
      expect(tester.widget<FxInkWell>(reviewItem).child, isA<ConstrainedBox>());

      await tester.tap(todayItem);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('X14 工具页隐藏底部导航并在返回后恢复', (tester) async {
      await pumpAt(tester, size: const Size(360, 800));
      await tester.tap(fxTooltipFinder('工具'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('四象限'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home.bottom-nav')), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home.bottom-nav')), findsOneWidget);
      await disposeFxTestHost(tester);
    });

    testWidgets('X14 Android 抽屉宽度与组织工具入口按主原型呈现',
        (tester) async {
      await pumpAt(tester, size: const Size(360, 800));
      await tester.tap(fxTooltipFinder('工具'));
      await tester.pumpAndSettle();

      final drawer = find.byType(Drawer);
      expect(drawer, findsOneWidget);
      expect(tester.getSize(drawer).width, closeTo(360 * .78, .01));
      expect(find.text('组织工具'), findsOneWidget);
      // Android shows both entries immediately, unlike Windows expansion.
      expect(find.text('清单'), findsOneWidget);
      expect(find.text('标签'), findsOneWidget);
      expect(fxTooltipFinder('关闭'), findsOneWidget);

      await tester.tap(find.text('清单'));
      await tester.pumpAndSettle();
      expect(find.byType(ListManageScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('home.bottom-nav')), findsNothing);
      await tester.tap(fxTooltipFinder('返回'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home.bottom-nav')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('X14 Android 412dp 抽屉/页头入口及关闭可达', (tester) async {
      await pumpAt(tester, size: const Size(412, 915), textScale: 1.3);
      expect(fxTooltipFinder('记录观察'), findsOneWidget);
      await tester.tap(fxTooltipFinder('工具'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Drawer)).width,
          closeTo(412 * .78, .01));
      await tester.tap(fxTooltipFinder('关闭'));
      await tester.pumpAndSettle();
      expect(fxTooltipFinder('记录观察'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('X14 Android 320dp 大字号抽屉保留可达与滚动布局', (tester) async {
      await pumpAt(tester, size: const Size(320, 640), textScale: 2);
      await tester.tap(fxTooltipFinder('工具'));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text('清单'), findsOneWidget);
      expect(find.text('标签'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('X14 抽屉本地同步只读、关于二级路由可返回',
        (tester) async {
      await pumpAt(tester, size: const Size(360, 800));
      await tester.tap(fxTooltipFinder('工具'));
      await tester.pumpAndSettle();
      final localStatus = find.text('本地数据');
      expect(localStatus, findsOneWidget);
      // A local-mode status badge must not open a cloud sync sheet.
      expect(find.ancestor(
        of: localStatus,
        matching: find.byType(FxGestureDetector),
      ), findsNothing);
      await tester.tap(fxTooltipFinder('关于'));
      await tester.pumpAndSettle();
      expect(find.byType(AboutScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home.bottom-nav')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('X14 Windows 组织工具继续使用已有折叠行为', (tester) async {
      await pumpAt(tester, size: const Size(1200, 800));
      expect(find.text('观察标签'), findsNothing);
      await tester.tap(find.text('组织工具'));
      await tester.pumpAndSettle();
      expect(find.text('清单'), findsOneWidget);
      expect(find.text('观察标签'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('X14 Android 页头随工具导航切换单一标题与返回操作',
        (tester) async {
      await pumpAt(tester, size: const Size(360, 800));
      final appBar = find.byType(AppBar);
      expect(appBar, findsOneWidget);
      expect(tester.widget<AppBar>(appBar).toolbarHeight, 48);
      expect(tester.widget<AppBar>(appBar).titleSpacing, 8);
      expect(fxTooltipFinder('工具'), findsOneWidget);
      expect(fxTooltipFinder('记录观察'), findsOneWidget);
      await tester.tap(fxTooltipFinder('工具'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('四象限'));
      await tester.pumpAndSettle();
      expect(fxTooltipFinder('返回'), findsOneWidget);
      expect(fxTooltipFinder('记录观察'), findsNothing);
      expect(find.byKey(const ValueKey('home.bottom-nav')), findsNothing);
      await tester.tap(fxTooltipFinder('返回'));
      await tester.pumpAndSettle();
      expect(fxTooltipFinder('工具'), findsOneWidget);
      expect(find.byKey(const ValueKey('home.bottom-nav')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('移动端只保留悬浮快速添加任务主入口', (tester) async {
      await pumpAt(tester, size: const Size(360, 800));
      expect(fxTooltipFinder('快速添加任务（按住可拖动）'), findsOneWidget);
      expect(fxTooltipFinder('添加任务'), findsNothing);
      expect(fxTooltipFinder('记录观察'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('Android 切换顶层页面后，连按返回退出窗口重新计时',
        (tester) async {
      await pumpAt(tester, size: const Size(360, 800));
      final exitCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') exitCalls.add(call);
          return null;
        },
      );
      addTearDown(() =>
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform, null,
          ));

      // Start the two-back exit window on Today.
      await tester.binding.handlePopRoute();
      await tester.pump();
      // Moving to Review must invalidate that pending exit gesture.
      await tester.tap(find.text('回顾').last);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(exitCalls, isEmpty);
      expect(find.text('再按一次退出 Slowlight'), findsWidgets);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('X15 降低动态效果时今天 FAB 的显示/隐藏动效立即完成',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildFxTestHost(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const HomeScreen(),
      ));
      await tester.pump();

      final fab = find.byKey(const ValueKey('today.fab.pointer'));
      expect(fab, findsOneWidget);
      final slide = find.descendant(of: fab, matching: find.byType(AnimatedSlide));
      final opacity = find.descendant(of: fab, matching: find.byType(AnimatedOpacity));
      expect(tester.widget<AnimatedSlide>(slide).duration, Duration.zero);
      expect(tester.widget<AnimatedOpacity>(opacity).duration, Duration.zero);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('今天与回顾切换不销毁今天工作台状态', (tester) async {
      await pumpAt(tester, size: const Size(360, 800));
      final today = find.byType(DashboardBody, skipOffstage: false);
      expect(today, findsOneWidget);
      final dashboardState = tester.state(today);

      await tester.tap(find.text('回顾').last);
      await tester.pump();
      expect(today, findsOneWidget);
      expect(identical(tester.state(today), dashboardState), isTrue);

      await tester.tap(find.text('今天').last);
      await tester.pump();
      expect(today, findsOneWidget);
      expect(identical(tester.state(today), dashboardState), isTrue);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('打开工具页再返回时保留今天状态及 FAB 入口', (tester) async {
      await pumpAt(tester, size: const Size(360, 800));
      final today = find.byType(DashboardBody, skipOffstage: false);
      final dashboardState = tester.state(today);

      await tester.tap(fxTooltipFinder('工具'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('四象限'));
      await tester.pumpAndSettle();
      expect(find.byType(QuadrantScreen), findsOneWidget);
      expect(identical(tester.state(today), dashboardState), isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(QuadrantScreen), findsNothing);
      expect(identical(tester.state(today), dashboardState), isTrue);
      final fab = fxTooltipFinder('快速添加任务（按住可拖动）');
      expect(fab, findsOneWidget);
      final ignoring = tester.widget<IgnorePointer>(
        find.byKey(const ValueKey('today.fab.pointer')),
      );
      expect(ignoring.ignoring, isFalse);
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

    testWidgets('Android 宽屏拖动后缩窄视口，FAB 下一次拖动不冻结', (tester) async {
      await pumpAt(tester, size: const Size(412, 915));
      final fab = fxTooltipFinder('快速添加任务（按住可拖动）');

      // Store a coordinate valid at 412dp but outside a 360dp body.
      await tester.drag(fab, const Offset(1, 0));
      await tester.pump();
      tester.view.physicalSize = const Size(360, 800);
      await tester.pump();

      final before = tester.getCenter(fab);
      expect(tester.getRect(fab).right, lessThanOrEqualTo(360));
      await tester.drag(fab, const Offset(-28, 0));
      await tester.pump();

      expect(tester.getCenter(fab).dx, lessThan(before.dx - 14));
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

    testWidgets('Windows 从任务工具切换到习惯时保护未保存详情草稿', (tester) async {
      final list = await DataService().createList(name: '草稿防丢失测试');
      final task = await DataService().createTask(
        listId: list.id,
        title: '尚待处理的工作',
        dueDate: DateTime.now(),
      );
      await pumpAt(tester, size: const Size(1200, 800));
      await tester.tap(find.text('任务').first);
      await tester.pumpAndSettle();
      expect(find.byType(TaskToolScreen), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('tasks.row.${task.id}')));
      await tester.pumpAndSettle();
      final title = find.descendant(
        of: find.byType(TaskDetailSheet),
        matching: find.byType(EditableText),
      ).first;
      await tester.enterText(title, '尚未保存的工作草稿');
      await tester.pump();

      await tester.tap(find.text('习惯').first);
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskToolScreen), findsOneWidget);
      expect(tester.widget<EditableText>(title).controller.text,
          '尚未保存的工作草稿');

      await tester.tap(find.text('习惯').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃修改'));
      await tester.pumpAndSettle();
      expect(find.byType(HabitToolScreen), findsOneWidget);
      expect(find.byType(TaskDetailSheet), findsNothing);
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
