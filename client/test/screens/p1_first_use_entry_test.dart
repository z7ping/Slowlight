import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/login_screen.dart';
import 'package:slowlight/widgets/dashboard/dashboard_body.dart';

import '../support/fx_test_host.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('首次进入保留云端优先，同时明确提示可以无需登录继续：$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = platform == TargetPlatform.android
          ? const Size(360, 800) : const Size(1180, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildFxTestHost(
        home: const LoginScreen(),
      ));
      await tester.pump();
      final local = find.byKey(const ValueKey('login.local_action'));
      expect(local, findsOneWidget);
      expect(find.textContaining('记录仅保存在当前设备'), findsOneWidget);
      expect(tester.getTopLeft(local).dy,
          greaterThan(tester.getTopLeft(find.text('欢迎回来')).dy));
      await tester.ensureVisible(local);
      await tester.tap(local);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('login.local_confirm')), findsOneWidget);
      expect(find.textContaining('不会自动上传或合并到云端'), findsOneWidget);
      expect(find.textContaining('迁移云端需要主动预览并确认'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }

  testWidgets('真正没有任务与习惯时，分别提供就近的低权重引导', (tester) async {
    var tasks = 0;
    var habits = 0;
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: DashboardBody(
        tasks: const [],
        habits: const [],
        onQuickAdd: () => tasks++,
        onViewAllHabits: () => habits++,
        dimensionLoader: () async => {'dimensions': []},
        reviewLoader: () async => {'questions': [], 'facts': {}},
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('先写下一件想做的事'), findsOneWidget);
    expect(find.text('去创建第一个习惯'), findsOneWidget);
    await tester.tap(find.text('先写下一件想做的事'));
    await tester.pump();
    await tester.tap(find.text('去创建第一个习惯'));
    await tester.pump();
    expect(tasks, 1);
    expect(habits, 1);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
