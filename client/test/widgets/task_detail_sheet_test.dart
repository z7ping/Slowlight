import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/ui/theme_manager.dart';
import 'package:slowlight/widgets/tag_picker.dart';
import 'package:slowlight/widgets/task_detail_sheet.dart';

import '../support/fx_test_host.dart';

void main() {
  final task = Task(
    id: 7,
    listId: 1,
    title: '研究课题',
    priority: 'none',
    isCompleted: false,
    systemTagId: 3,
    createdAt: DateTime(2026, 10, 16),
  );
  final lists = [
    TodoList(
      id: 1,
      name: '工作',
      color: '#1890ff',
      createdAt: DateTime(2026, 10, 16),
    ),
  ];

  testWidgets('新建任务与详情共享相同字段树，并仅在输入标题后可创建',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final draft = Task(
      id: 0,
      listId: 1,
      title: '',
      priority: 'none',
      dueDate: DateTime(2026, 11, 5),
      isCompleted: false,
      createdAt: DateTime(2026, 11, 5),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskDetailSheet(
          task: draft,
          isCreating: true,
          lists: lists,
          onChanged: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('新建任务'), findsOneWidget);
    expect(find.text('任务详情'), findsNothing);
    expect(tester.widget<FxInput>(
      find.byKey(const ValueKey('task.detail.title')),
    ).plain, isTrue);
    for (final field in ['list', 'due', 'priority', 'tags']) {
      expect(find.byKey(ValueKey('task.detail.property.$field')),
          findsOneWidget);
    }
    expect(find.byKey(const ValueKey('task.detail.complete')), findsOneWidget);
    expect(find.byType(FxMenu<String>), findsNWidgets(4));
    final action = find.byKey(const ValueKey('task.detail.primaryAction'));
    expect(find.text('创建任务'), findsOneWidget);
    expect(tester.widget<FxButton>(action).onPressed, isNull);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('task.detail.title')),
        matching: find.byType(EditableText),
      ),
      '写下明天的计划',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FxButton>(action).onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('task.detail.property.priority')));
    await tester.pumpAndSettle();
    expect(find.text('不重要 · 不紧急'), findsOneWidget);
    await tester.tap(find.text('高'));
    await tester.pumpAndSettle();
    expect(find.text('新建任务'), findsOneWidget);
    expect(find.text('尚未创建'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 任务新建携带来自日历的日期和四象限优先级',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(
          builder: (context) => FxButton(
            label: '打开创建',
            onPressed: () => TaskDetailSheet.showCreate(
              context,
              lists: lists,
              onChanged: () {},
              initialDueDate: DateTime(2026, 11, 21),
              initialPriority: 'urgent_important',
              defaultDueToday: false,
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开创建'));
    await tester.pumpAndSettle();

    final detail = find.byType(TaskDetailSheet);
    expect(detail, findsOneWidget);
    final draft = tester.widget<TaskDetailSheet>(detail).task;
    expect(draft.dueDate, DateTime(2026, 11, 21));
    expect(draft.priority, 'urgent_important');
    expect(tester.widget<TaskDetailSheet>(detail).isCreating, isTrue);
    expect(find.text('新建任务'), findsOneWidget);
    expect(find.text('高'), findsOneWidget);
    expect(find.text('2026-11-21'), findsOneWidget);
    final title = find.descendant(
      of: find.byKey(const ValueKey('task.detail.title')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(title).focusNode.hasFocus, isTrue);
    // The main form grows with content but never occupies the whole viewport.
    expect(tester.getSize(detail).height, lessThan(820));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 重新选中相同优先级不误报未保存',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskDetailSheet(
          task: task,
          lists: lists,
          onChanged: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task.detail.property.priority')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不重要 · 不紧急'));
    await tester.pumpAndSettle();
    expect(find.text('已保存'), findsOneWidget);
    expect(find.text('有未保存的修改'), findsNothing);
    expect(
      tester.widget<FxButton>(
        find.byKey(const ValueKey('task.detail.primaryAction')),
      ).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 任务详情显示核心属性，使用同一 Sheet 内的编辑视图',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskDetailSheet(
          task: task,
          lists: lists,
          onChanged: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('任务详情'), findsOneWidget);
    expect(find.byKey(const ValueKey('task.detail.title')), findsOneWidget);
    expect(tester.widget<FxInput>(
      find.byKey(const ValueKey('task.detail.title')),
    ).plain, isTrue);
    expect(find.byKey(const ValueKey('task.detail.property.list')), findsOneWidget);
    expect(find.byKey(const ValueKey('task.detail.property.due')), findsOneWidget);
    expect(find.byKey(const ValueKey('task.detail.property.priority')), findsOneWidget);
    expect(find.byKey(const ValueKey('task.detail.property.tags')), findsOneWidget);
    expect(find.byKey(const ValueKey('task.detail.property.repeat')), findsNothing);
    expect(find.text('时间安排'), findsNothing);
    expect(find.byType(TagPicker), findsNothing);
    expect(find.text('历史分类（兼容）'), findsNothing);
    expect(find.text('保存修改'), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('task.detail.property.priority')));
    await tester.pumpAndSettle();
    expect(find.text('设置优先级'), findsOneWidget);
    expect(find.text('高'), findsOneWidget);
    await tester.tap(find.text('高'));
    await tester.pumpAndSettle();
    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('有未保存的修改'), findsOneWidget);
    final save = tester.widget<FxButton>(
        find.byKey(const ValueKey('task.detail.primaryAction')));
    expect(save.onPressed, isNotNull);

    await tester.ensureVisible(find.byKey(const ValueKey('task.detail.property.tags')));
    await tester.tap(find.byKey(const ValueKey('task.detail.property.tags')));
    await tester.pumpAndSettle();
    expect(find.byType(TagPicker), findsOneWidget);
    expect(find.text('历史分类（兼容）'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 重复属性支持每周选日且不立即保存',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskDetailSheet(task: task, lists: lists, onChanged: () {}),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task.detail.moreSettings')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('task.detail.property.repeat')));
    await tester.tap(find.byKey(const ValueKey('task.detail.property.repeat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每周'));
    await tester.pumpAndSettle();
    expect(find.text('选择星期'), findsOneWidget);
    expect(find.byType(FxChoiceChip), findsNWidgets(7));
    expect(find.text('有未保存的修改'), findsOneWidget);
    expect(find.text('修改后返回详情'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('Android 360dp 大字号 $scale 下核心属性与底部保存可达',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(360, 880);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildFxTestHost(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: TaskDetailSheet(
            task: task,
            lists: lists,
            onChanged: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('task.detail.property.list')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('task.detail.primaryAction')),
          findsOneWidget);
      final save = find.byKey(const ValueKey('task.detail.primaryAction'));
      expect(tester.getSize(save).height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }

  testWidgets('Android 暗色 320dp 高字号弹层保持可滚动和固定保存入口',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      theme: ThemeManager.darkTheme,
      shadTheme: ThemeManager.shadDark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.3),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: TaskDetailSheet(task: task, lists: lists, onChanged: () {}),
      ),
    ));
    await tester.pumpAndSettle();

    final footer = find.byKey(const ValueKey('task.detail.primaryAction'));
    expect(footer, findsOneWidget);
    final rect = tester.getRect(footer);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
    expect(rect.bottom, lessThanOrEqualTo(640));
    final more = find.byKey(const ValueKey('task.detail.moreSettings'));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task.detail.property.repeat')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows 任务详情保留紧凑右侧面板操作区', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 720,
          child: TaskDetailSheet(
            task: task,
            lists: lists,
            sidePanel: true,
            onChanged: () {},
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byType(FxMenu<String>), findsNothing);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('保存修改'), findsOneWidget);
    expect(find.text('历史分类（兼容）'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
