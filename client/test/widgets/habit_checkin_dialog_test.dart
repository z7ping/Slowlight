import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/habit_checkin_dialog.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('Android 习惯打卡主按钮与取消按钮遵循 6:4 布局', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final habit = Habit(
      id: 11,
      userId: 1,
      name: '读书',
      recordType: 'check',
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitCheckinDialog(habit: habit)),
    ));
    await tester.pump();
    final action = find.byKey(const ValueKey('habit-checkin-primary-action'));
    expect(action, findsOneWidget);
    final cancel = find.widgetWithText(FxButton, '取消');
    expect(cancel, findsOneWidget);
    final primaryWidth = tester.getSize(action).width;
    final cancelWidth = tester.getSize(cancel).width;
    expect(primaryWidth, greaterThan(cancelWidth));
    expect(primaryWidth / cancelWidth, closeTo(1.5, .08));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 习惯记录想法置顶且默认不唤起键盘', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final habit = Habit(
      id: 31,
      userId: 1,
      name: '读书',
      recordType: 'duration',
      durationMin: 30,
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitCheckinDialog(habit: habit)),
    ));
    await tester.pumpAndSettle();

    final thoughts = find.byKey(const ValueKey('habit-checkin-thoughts'));
    expect(thoughts, findsOneWidget);
    expect(find.text('此刻的想法（选填）'), findsOneWidget);
    expect(find.text('备注（选填）'), findsNothing);
    expect(tester.widget<FxInput>(thoughts).minLines, 3);
    expect(tester.widget<FxInput>(thoughts).maxLines, 6);
    expect(tester.getSize(thoughts).height, inInclusiveRange(88, 160));
    expect(tester.getTopLeft(thoughts).dy,
        lessThan(tester.getTopLeft(find.text('实际时长')).dy));
    expect(tester.widget<EditableText>(
      find.descendant(of: thoughts, matching: find.byType(EditableText)),
    ).focusNode.hasFocus, isFalse);
    expect(find.byKey(const ValueKey('habit-checkin-more-durations')),
        findsNothing);
    expect(find.byKey(const ValueKey('habit-checkin-quick-durations')),
        findsOneWidget);

    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('habit-checkin-more-durations')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('habit-checkin-custom-duration')),
        findsOneWidget);
    await tester.enterText(find.descendant(
      of: find.byKey(const ValueKey('habit-checkin-custom-duration')),
      matching: find.byType(EditableText),
    ), '25');
    await tester.tap(find.text('使用'));
    await tester.pumpAndSettle();
    expect(find.text('25 分钟'), findsOneWidget);
    expect(find.byKey(const ValueKey('habit-checkin-more-durations')),
        findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

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
    expect(tester.widget<EditableText>(find.byType(EditableText).last)
        .controller.text, '今天读完了一章');

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
