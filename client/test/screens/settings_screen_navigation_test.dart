import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/screens/settings_screen.dart';

import '../support/fx_test_host.dart';

void main() {
  setUp(() {
    // 避免测试中触发真实云端账号请求，错误状态仍需正常渲染设置导航。
    SharedPreferences.setMockInitialValues({'user_data': 'invalid-data'});
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
}
