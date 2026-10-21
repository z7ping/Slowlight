import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/repositories/habit_repository.dart';
import 'package:slowlight/screens/habit_tool_screen.dart';
import 'package:slowlight/widgets/habit_editor_dialog.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

class _EmptyHabitRepo extends HabitRepository {
  @override
  Future<List<Habit>> getAll() async => [];
}

void main() {
  testWidgets('09 Android 360dp 普通字体的习惯数与添加操作同排', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitToolScreen(repository: _EmptyHabitRepo())),
    ));
    await tester.pumpAndSettle();

    final summary = tester.getRect(find.text('0 个习惯'));
    final action = tester.getRect(find.text('添加习惯'));
    expect((summary.center.dy - action.center.dy).abs(), lessThan(24));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('09 Android 超大字体仍可访问习惯添加', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(body: HabitToolScreen(repository: _EmptyHabitRepo())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('添加习惯'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
  testWidgets('习惯编辑名称为空不静默失败，错误数字不再变成 0', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: const Scaffold(body: HabitEditorDialog()),
    ));
    await tester.pump();

    await tester.tap(find.text('创建习惯'));
    await tester.pump();
    expect(find.text('请填写习惯名称'), findsOneWidget);

    await tester.enterText(find.byType(FxInput).first, '每日阅读');
    await tester.enterText(find.byType(FxInput).at(1), '错误数字');
    await tester.tap(find.text('创建习惯'));
    await tester.pump();
    expect(find.text('目标天数必须是 0 或正整数'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
