import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/add_task_screen.dart';
import 'package:slowlight/screens/task_create_sheet.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/task_schedule_fields.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('Android 平板宽度超过 600dp 仍进入完整任务页面而非桌面弹窗', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(840, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final lists = [
      TodoList(id: 1, name: '工作', color: '#3B82F6', createdAt: DateTime(2026)),
    ];
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(
          builder: (context) => FxButton(
            onPressed: () {
              TaskCreateSheet.showFullCreate(context, lists: lists);
            },
            label: '打开完整表单',
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开完整表单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AddTaskScreen), findsOneWidget);
    expect(tester.widget<AddTaskScreen>(find.byType(AddTaskScreen)).embedded, isFalse);
    expect(find.text('新建任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('快捷任务在原弹窗展开高级设置并保持已输入标题', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: SizedBox(
          width: 520,
          height: 640,
          child: const TaskCreateSheet(quickMode: true, desktopDialog: true),
        ),
      ),
    ));
    await tester.pump();

    await tester.enterText(find.byType(EditableText).first, '季度复盘');
    await tester.tap(find.text('更多设置'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('收起设置'), findsOneWidget);
    expect(find.byType(AddTaskScreen), findsNothing);
    expect(find.byType(TaskScheduleFields), findsOneWidget);
    expect(find.text('到期日期'), findsOneWidget);
    expect(find.text('重复'), findsOneWidget);
    expect(find.text('提醒'), findsOneWidget);
    expect(find.text('季度复盘'), findsOneWidget);
    expect(find.text('添加任务'), findsOneWidget);

    await tester.tap(find.text('收起设置'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TaskScheduleFields), findsNothing);
    expect(find.text('季度复盘'), findsOneWidget);

    await tester.tap(find.text('更多设置'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TaskScheduleFields), findsOneWidget);
    expect(find.text('季度复盘'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 窄屏展开后可滚动，底部操作仍可见', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: const Scaffold(
        body: TaskCreateSheet(quickMode: true),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('更多设置'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TaskScheduleFields), findsOneWidget);
    expect(find.text('收起设置'), findsOneWidget);
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -260));
    await tester.pump();
    expect(find.text('收起设置'), findsOneWidget);
    expect(find.text('添加任务'), findsWidgets);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  test('快捷与完整表单复用相同的日程存储规则', () {
    expect(formatTaskDueTime(const TimeOfDay(hour: 9, minute: 5)), '09:05');
    expect(formatTaskRepeatDays('weekly', {3, 1}), '1,3');
    expect(formatTaskRepeatDays('daily', {3, 1}), '');
    expect(
      buildTaskReminderAt(
        dueDate: DateTime(2026, 10, 19),
        dueTime: const TimeOfDay(hour: 10, minute: 0),
        advanceMinutes: 15,
      ),
      DateTime(2026, 10, 19, 9, 45),
    );
  });

  group('TaskCreateSheet', () {
    test('快速创建默认使用无优先级并安排到今天', () {
      const sheet = TaskCreateSheet(quickMode: true);

      expect(sheet.initialPriority, 'none');
      expect(sheet.defaultDueToday, isTrue);
    });

    test('四象限入口可以预设优先级且不强制安排到今天', () {
      const sheet = TaskCreateSheet(
        quickMode: true,
        initialPriority: 'important',
        defaultDueToday: false,
      );

      expect(sheet.initialPriority, 'important');
      expect(sheet.defaultDueToday, isFalse);
    });
  });
}
