import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/habit_checkin_dialog.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('X06 Windows 取消和 Escape 均保护打卡草稿', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final habit = Habit(
      id: 20,
      userId: 1,
      name: '专注阅读',
      recordType: 'check',
      createdAt: DateTime.now(),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '打开习惯记录',
          onPressed: () => HabitCheckinDialog.show(context, habit: habit),
        ),
      )),
    ));
    await tester.tap(find.text('打开习惯记录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, '今天读完了一章');
    await tester.pump();

    await tester.tap(find.widgetWithText(FxButton, '取消').first);
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的记录？'), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(find.text('今天读完了一章'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的记录？'), findsOneWidget);
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.text('专注阅读'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X06 Windows 结果未确认时取消必须提示核对', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final habit = Habit(
      id: 21,
      userId: 1,
      name: '待核对记录',
      recordType: 'check',
      createdAt: DateTime.now(),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '打开待核对记录',
          onPressed: () => HabitCheckinDialog.show(
            context,
            habit: habit,
            pendingValue: const {'note': '网络中断前已提交'},
            initialError: '保存结果未确认',
          ),
        ),
      )),
    ));
    await tester.tap(find.text('打开待核对记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FxButton, '取消').first);
    await tester.pumpAndSettle();
    expect(find.text('打卡结果未确认'), findsOneWidget);
    await tester.tap(find.text('返回核对'));
    await tester.pumpAndSettle();
    expect(find.text('待核对记录'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
