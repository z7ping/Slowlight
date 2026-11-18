import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/services/data_mode_manager.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/widgets/habit_editor_dialog.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';
import '../helpers/isolated_test_db.dart';

void main() {
  setUpAll(() async {
    await useIsolatedTestDb('habit_editor_v3_recovery');
    SharedPreferences.setMockInitialValues({'data_mode': 'local'});
    FlutterSecureStorage.setMockInitialValues({});
    await DataModeManager().setLocal();
  });
  testWidgets('X05 未确认草稿重新打开时完整回填 V3 频率规则', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final draft = HabitEditorValue(
      name: '间隔阅读',
      icon: '📚',
      color: '#1890ff',
      frequency: 'custom',
      targetDays: 0,
      systemTagId: null,
      preferredPeriod: 'evening',
      durationMin: 0,
      generateTask: false,
      showCheckinDialog: true,
      specificTime: '',
      reminderAt: const {'enabled': false},
      scheduleRule: const {
        'kind': 'specific',
        'unit': 'month',
        'every': 2,
        'anchor_date': '2026-07-15',
        'anchor_time': '17:30',
        'month_days': [7, 21],
        'weekdays': [1, 3],
        'last_day': true,
        'target_count': 3,
        'reminder_mode': 'daily',
        'reminder_time': '18:45',
      },
    );
    HabitEditorValue? saved;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
          body: HabitEditorDialog(
        initialValue: draft,
        onSubmit: (value) async {
          saved = value;
        },
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

  testWidgets('X05 旧习惯无计划时间时不覆盖原 V3 起算时刻和提醒时刻', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final habit = Habit(
      id: 505,
      userId: 1,
      name: '旧 V3 习惯',
      specificTime: '',
      reminderAt: const {'enabled': false},
      scheduleRule: const {
        'kind': 'interval',
        'unit': 'day',
        'every': 3,
        'anchor_date': '2026-06-01',
        'anchor_time': '06:35',
        'reminder_mode': 'off',
        'reminder_time': '20:10',
      },
      createdAt: DateTime(2026, 1, 1),
    );
    HabitEditorValue? saved;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
          body: HabitEditorDialog(
        habit: habit,
        onSubmit: (value) async {
          saved = value;
        },
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

  testWidgets('X05 旧习惯改名时保留空排程与原频率', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final habit = Habit(
      id: 506,
      userId: 1,
      name: '旧习惯',
      frequency: 'custom',
      specificTime: '19:30',
      reminderAt: const {'enabled': true, 'hour': 19, 'minute': 20},
      createdAt: DateTime(2026, 1, 1),
    );
    HabitEditorValue? saved;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: HabitEditorDialog(habit: habit, onSubmit: (value) async {
          saved = value;
        }),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(FxInput).first, '新名称');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(saved?.name, '新名称');
    expect(saved?.frequency, 'custom');
    expect(saved?.scheduleRule, isEmpty);
    expect(saved?.specificTime, '19:30');
    expect(saved?.reminderAt, habit.reminderAt);
    await disposeFxTestHost(tester);
  });

  testWidgets('X05 主动修改旧习惯的排程时提交 V3 规则', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final habit = Habit(
      id: 507,
      userId: 1,
      name: '旧周计划',
      frequency: 'weekly',
      createdAt: DateTime(2026, 1, 1),
    );
    HabitEditorValue? saved;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: HabitEditorDialog(habit: habit, onSubmit: (value) async {
          saved = value;
        }),
      ),
    ));
    await tester.pumpAndSettle();
    final every = find.byWidgetPredicate(
      (widget) => widget is FxInput && widget.label == '每 N 小时/天/周/月',
    );
    await tester.ensureVisible(every);
    await tester.enterText(every, '2');
    final anchor = find.byWidgetPredicate(
      (widget) => widget is FxInput && widget.placeholder == 'YYYY-MM-DD',
    );
    await tester.ensureVisible(anchor);
    await tester.enterText(anchor, '2026-01-01');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(saved?.frequency, 'custom');
    expect(saved?.scheduleRule['unit'], 'week');
    expect(saved?.scheduleRule['every'], 2);
    expect(saved?.scheduleRule['anchor_date'], '2026-01-01');
    await disposeFxTestHost(tester);
  });

  testWidgets('X05 Windows 取消编辑必须先确认未保存的草稿', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
          body: Builder(
        builder: (context) => FxButton(
          label: '打开编辑器',
          onPressed: () => unawaited(HabitEditorDialog.show(context)),
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

  testWidgets('P1-8 切到周期目标再返回固定间隔保留原按计划提醒草稿', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: const Scaffold(body: HabitEditorDialog()),
    ));
    await tester.pumpAndSettle();

    FxSegmented segment(String label) => tester
        .widgetList<FxSegmented>(
          find.byType(FxSegmented),
        )
        .firstWhere((item) => item.labels.contains(label));

    segment('按计划').onChanged(1);
    await tester.pump();
    expect(segment('按计划').selectedIndex, 1);

    segment('周期目标').onChanged(2);
    await tester.pump();
    // A goal has no fixed planned instant. Do not persist an invalid mode.
    final goalReminder = segment('每天定时');
    expect(goalReminder.labels, ['不提醒', '每天定时']);
    expect(goalReminder.selectedIndex, 1);

    segment('周期目标').onChanged(0);
    await tester.pump();
    // Returning to the original mode restores the user's unsaved choice.
    expect(segment('按计划').selectedIndex, 1);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
