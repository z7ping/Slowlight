import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/screens/settings_screen.dart';
import 'package:slowlight/services/reminder_service.dart';

import '../support/fx_test_host.dart';

void main() {
  setUp(() {
    // 避免测试中触发真实云端账号请求，错误状态仍需正常渲染设置导航。
    SharedPreferences.setMockInitialValues({'user_data': 'invalid-data'});
  });

  testWidgets('P17 编辑外观时，休息时钟事件不重建整个设置页', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1250, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: const SettingsScreen(initialSection: 'appearance'),
    ));
    await tester.pump();

    const key = PageStorageKey('settings.overview');
    final listBefore = tester.widget<ListView>(find.byKey(key));
    final reminder = ReminderService();
    reminder.updateConfig(notifyBeforeSec: reminder.notifyBeforeSec);
    await tester.pump();
    final listAfter = tester.widget<ListView>(find.byKey(key));
    expect(identical(listBefore, listAfter), isTrue);
    expect(find.byKey(const ValueKey('settings.category.appearance')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P17 Windows 窄窗从休息详情返回后，计时不再重建分类首页',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(720, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: const SettingsScreen(),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings.category.rest')));
    await tester.pump();
    expect(find.text('休息提醒'), findsWidgets);
    await tester.tap(find.byTooltip('返回').first);
    await tester.pump();

    const key = PageStorageKey('settings.overview');
    final before = tester.widget<ListView>(find.byKey(key));
    final reminder = ReminderService();
    reminder.updateConfig(notifyBeforeSec: reminder.notifyBeforeSec);
    await tester.pump();
    final after = tester.widget<ListView>(find.byKey(key));
    expect(identical(before, after), isTrue);
    expect(find.byKey(const ValueKey('settings.category.rest')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P17 移动设置二级详情返回分类，不另起设置路由', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: const SettingsScreen(),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings.category.privacy')));
    await tester.pump();
    expect(find.text('当前记录来源'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.category.privacy')),
        findsNothing);
    await tester.tap(find.byTooltip('返回').first);
    await tester.pump();
    expect(find.byKey(const ValueKey('settings.category.privacy')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 设置为分类首页，隐藏桌面休息入口', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(buildFxTestHost(
      home: const SettingsScreen(),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('settings.category.appearance')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.category.data')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.category.sync')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.category.diagnostics')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.category.rest')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings.category.data')));
    await tester.pump();
    expect(find.text('预览迁移'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.category.data')), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('宽布局为内部双栏，分类切换不叠加页面路由', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(1250, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(buildFxTestHost(
      home: const SettingsScreen(),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('settings.category.appearance')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings.category.privacy')));
    await tester.pump();
    expect(find.text('当前记录来源'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.category.appearance')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
  testWidgets('单列设置项的摘要与箭头整体靠右，且所有箭头位置一致', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(720, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(home: const SettingsScreen()));
    await tester.pump();

    final appearance = tester.getRect(
      find.byKey(const ValueKey('settings.category.appearance')),
    );
    final summary = tester.getRect(
      find.byKey(const ValueKey('settings.summary.appearance')),
    );
    final arrow = tester.getRect(
      find.byKey(const ValueKey('settings.chevron.appearance')),
    );
    final accountArrow = tester.getRect(
      find.byKey(const ValueKey('settings.chevron.account')),
    );

    expect(summary.right, lessThan(arrow.left));
    expect(summary.left, greaterThan(appearance.center.dx));
    expect(appearance.right - arrow.right, closeTo(14, 2));
    expect(arrow.right, closeTo(accountArrow.right, 1));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 窄屏保留副标题在下方，不挤压标签和箭头', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(home: const SettingsScreen()));
    await tester.pump();

    expect(find.text('主题、配色、字体与显示'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.summary.appearance')), findsNothing);
    expect(find.byKey(const ValueKey('settings.chevron.appearance')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('大字体的单列设置项回退至上下排版', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(720, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: const SettingsScreen(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
    ));
    await tester.pump();

    expect(find.text('主题、配色、字体与显示'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings.summary.appearance')), findsNothing);
    expect(find.byKey(const ValueKey('settings.chevron.appearance')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
