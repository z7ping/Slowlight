import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/add_task_screen.dart';
import 'package:slowlight/screens/task_create_sheet.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/tag_choice_field.dart';
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

  testWidgets('快捷添加任务标签默认展开且可以收起再打开', (tester) async {
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

    expect(find.byType(TagChoiceField), findsOneWidget);
    expect(find.text('无标签'), findsOneWidget);
    expect(find.text('收起标签'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, '整理资料');
    await tester.tap(find.text('收起标签'));
    await tester.pump();
    expect(find.byType(TagChoiceField), findsNothing);
    expect(find.text('标签'), findsOneWidget);

    await tester.tap(find.text('标签'));
    await tester.pump();
    expect(find.byType(TagChoiceField), findsOneWidget);
    expect(find.text('整理资料'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 窄屏默认显示两列任务属性和固定操作栏', (tester) async {
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
    for (final key in [
      'task-property-list',
      'task-property-date',
      'task-property-priority',
      'task-property-tag',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.byType(TagChoiceField), findsNothing);
    expect(find.text('无标签'), findsOneWidget);
    expect(find.text('详细设置'), findsOneWidget);
    expect(find.text('添加任务'), findsWidgets);
    final list = tester.getTopLeft(find.byKey(const ValueKey('task-property-list')));
    final date = tester.getTopLeft(find.byKey(const ValueKey('task-property-date')));
    final priority = tester.getTopLeft(find.byKey(const ValueKey('task-property-priority')));
    final tag = tester.getTopLeft(find.byKey(const ValueKey('task-property-tag')));
    expect(list.dy, closeTo(date.dy, 1));
    expect(priority.dy, closeTo(tag.dy, 1));
    expect(priority.dy, greaterThan(date.dy));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 四项属性使用原业务状态，选择后立即回填', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: const Scaffold(body: TaskCreateSheet(quickMode: true)),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('task-property-priority')));
    await tester.pumpAndSettle();
    expect(find.text('设置优先级'), findsOneWidget);
    await tester.tap(find.text('高'));
    await tester.pumpAndSettle();
    expect(find.text('高'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('task-property-date')));
    await tester.pumpAndSettle();
    expect(find.text('安排日期'), findsOneWidget);
    await tester.tap(find.text('不安排日期'));
    await tester.pumpAndSettle();
    expect(find.text('未安排'), findsOneWidget);

    await tester.tap(find.text('详细设置'));
    await tester.pump(const Duration(milliseconds: 250));
    final schedule = tester.widget<TaskScheduleFields>(find.byType(TaskScheduleFields));
    expect(schedule.compact, isTrue);
    expect(schedule.dueDate, isNull);
    expect(find.text('收起设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 快捷添加任务不抢焦点，点击选项能收起键盘且保留标题', (tester) async {
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

    final input = tester.widget<FxInput>(find.byType(FxInput).first);
    expect(input.autofocus, isFalse);
    expect(input.onPressedOutside, isNotNull);

    final editable = find.byType(EditableText).first;
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isFalse);

    await tester.tap(editable);
    await tester.pump();
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    await tester.enterText(editable, '买一本书');

    await tester.tap(find.byKey(const ValueKey('task-property-tag')));
    await tester.pump();
    expect(find.text('选择标签'), findsOneWidget);
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isFalse);
    await tester.tap(find.text('无标签').last);
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(editable).controller.text, '买一本书');

    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 即使内容无需滚动也可通过拖动收起键盘', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: const Scaffold(
        body: TaskCreateSheet(quickMode: true),
      ),
    ));
    await tester.pump();

    final scroller = find.byType(SingleChildScrollView).first;
    final scrollWidget = tester.widget<SingleChildScrollView>(scroller);
    expect(scrollWidget.physics, isA<AlwaysScrollableScrollPhysics>());
    expect(
      scrollWidget.keyboardDismissBehavior,
      ScrollViewKeyboardDismissBehavior.onDrag,
    );

    final editable = find.byType(EditableText).first;
    await tester.tap(editable);
    await tester.pump();
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);

    await tester.drag(scroller, const Offset(0, -100));
    await tester.pump();
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('实际 Android 底部弹层支持拖动收起输入键盘', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(
          builder: (context) => FxButton(
            label: '打开快捷添加',
            onPressed: () => TaskCreateSheet.showQuickCreate(context),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开快捷添加'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(TaskCreateSheet), findsOneWidget);
    final editable = find.byType(EditableText).first;
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isFalse);

    await tester.tap(editable);
    await tester.pump();
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -120));
    await tester.pump();
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TaskCreateSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows 快捷任务仍默认聚焦标题以便快速输入', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(buildFxTestHost(
      home: const Scaffold(
        body: SizedBox(
          width: 520,
          height: 640,
          child: TaskCreateSheet(quickMode: true, desktopDialog: true),
        ),
      ),
    ));
    await tester.pump();

    expect(tester.widget<FxInput>(find.byType(FxInput).first).autofocus, isTrue);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 超短屏展开后可滚动，底部操作仍可见', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 440);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: const Scaffold(
        body: TaskCreateSheet(quickMode: true),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('详细设置'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TaskScheduleFields), findsOneWidget);
    expect(tester.widget<TaskScheduleFields>(find.byType(TaskScheduleFields)).compact, isTrue);
    expect(find.text('收起设置'), findsOneWidget);
    final scroll = find.byType(SingleChildScrollView).first;
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.drag(scroll, const Offset(0, -260));
    await tester.pump();
    expect(scrollable.position.pixels, greaterThan(0));
    expect(find.text('收起设置'), findsOneWidget);
    expect(find.text('添加任务'), findsWidgets);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 大字体下紧凑日程网格自动回退单列', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 740),
          textScaler: TextScaler.linear(2),
        ),
        child: const Scaffold(body: TaskCreateSheet(quickMode: true)),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('详细设置'));
    await tester.pump(const Duration(milliseconds: 250));

    final fields = tester.widget<TaskScheduleFields>(find.byType(TaskScheduleFields));
    expect(fields.compact, isTrue);
    expect(find.text('到期日期'), findsOneWidget);
    expect(find.text('时间'), findsOneWidget);
    // 双列宽度不足时自动退为单列，不截断字段标题。
    expect(
      tester.getTopLeft(find.text('时间')).dy,
      greaterThan(tester.getTopLeft(find.text('到期日期')).dy),
    );
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
