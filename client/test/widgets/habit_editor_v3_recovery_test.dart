import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/widgets/habit_editor_dialog.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('X05 未确认草稿重新打开时完整回填 V3 频率规则', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final draft = HabitEditorValue(
      name: '间隔阅读', icon: '📚', color: '#1890ff',
      frequency: 'custom', targetDays: 0, systemTagId: null,
      preferredPeriod: 'evening', durationMin: 0,
      generateTask: false, showCheckinDialog: true, specificTime: '',
      reminderAt: const {'enabled': false},
      scheduleRule: const {
        'kind': 'specific', 'unit': 'month', 'every': 2,
        'anchor_date': '2026-07-15', 'anchor_time': '17:30',
        'month_days': [7, 21], 'weekdays': [1, 3],
        'last_day': true, 'target_count': 3,
        'reminder_mode': 'daily', 'reminder_time': '18:45',
      },
    );
    HabitEditorValue? saved;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitEditorDialog(
        initialValue: draft,
        onSubmit: (value) async { saved = value; },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('已恢复上次未确认的草稿'), findsOneWidget);
    await tester.ensureVisible(find.text('已核对，允许重新保存'));
    await tester.tap(find.text('已核对，允许重新保存'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('创建习惯'));
    await tester.tap(find.text('创建习惯'));
    await tester.pump();
    final rule = saved?.scheduleRule;
    expect(rule, isNotNull);
    expect(rule?['kind'], 'specific');
    expect(rule?['unit'], 'month');
    expect(rule?['every'], 2);
    expect(rule?['month_days'], [7, 21]);
    expect(rule?['last_day'], isTrue);
    expect(rule?['anchor_date'], '2026-07-15');
    expect(rule?['anchor_time'], '17:30');
    expect(rule?['reminder_mode'], 'daily');
    expect(rule?['reminder_time'], '18:45');
    await disposeFxTestHost(tester);
  });

  testWidgets('X05 旧习惯无计划时间时不覆盖原 V3 起算时刻和提醒时刻',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final habit = Habit(
      id: 505, userId: 1, name: '旧 V3 习惯',
      specificTime: '', reminderAt: const {'enabled': false},
      scheduleRule: const {
        'kind': 'interval', 'unit': 'day', 'every': 3,
        'anchor_date': '2026-06-01', 'anchor_time': '06:35',
        'reminder_mode': 'off', 'reminder_time': '20:10',
      }, createdAt: DateTime(2026, 1, 1),
    );
    HabitEditorValue? saved;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: HabitEditorDialog(
        habit: habit,
        onSubmit: (value) async { saved = value; },
      )),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(saved?.scheduleRule['anchor_time'], '06:35');
    expect(saved?.scheduleRule['reminder_time'], '20:10');
    expect(saved?.scheduleRule['every'], 3);
    await disposeFxTestHost(tester);
  });

  testWidgets('X05 Windows 取消编辑必须先确认未保存的草稿', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '打开编辑器',
          onPressed: () => HabitEditorDialog.show(context),
        ),
      )),
    ));
    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(FxInput).first, '未保存的习惯名称');
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的习惯？'), findsOneWidget);
    expect(find.byType(HabitEditorDialog), findsOneWidget);
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitEditorDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
