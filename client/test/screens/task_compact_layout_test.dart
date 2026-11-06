import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/task_tool_screen.dart';
import 'package:slowlight/widgets/task_detail_sheet.dart';
import 'package:slowlight/widgets/task_swipe_row.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  for (final create in [true, false]) {
    testWidgets('任务页${create ? '新建' : '查看详情'}打开同一任务编辑组件',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final task = Task(
        id: 42,
        listId: 7,
        title: '已有的任务',
        priority: 'none',
        isCompleted: false,
        createdAt: DateTime.now(),
      );
      final list = TodoList(
        id: 7, name: '收集箱', isInbox: true, color: '#8db5a0',
        createdAt: DateTime.now(),
      );
      await tester.pumpWidget(buildFxTestHost(
        home: Scaffold(
          body: TaskToolScreen(
            dataLoader: () async => <dynamic>[
              <Task>[task],
              <Task>[task],
              <Task>[],
              <TodoList>[list],
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      if (create) {
        await tester.tap(find.text('新建'));
      } else {
        await tester.tap(find.text('已有的任务'));
      }
      await tester.pumpAndSettle();
      final detail = find.byType(TaskDetailSheet);
      expect(detail, findsOneWidget);
      expect(tester.widget<TaskDetailSheet>(detail).isCreating, create);
      for (final field in ['list', 'due', 'priority', 'tags']) {
        expect(find.byKey(ValueKey('task.detail.property.$field')),
            findsOneWidget);
      }
      expect(find.byKey(const ValueKey('task.detail.primaryAction')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }

  testWidgets('Android 任务列表按原型呈现轻量新建、下划线筛选和紧凑行',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final pending = Task(
      id: 31, listId: 1, title: '认真阅读',
      priority: 'important', isCompleted: false, createdAt: now,
    );
    final completed = Task(
      id: 32, listId: 1, title: '整理清单',
      priority: 'none', isCompleted: true,
      completedAt: now, createdAt: now,
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(
          dataLoader: () async => <dynamic>[
            <Task>[pending],
            <Task>[pending, completed],
            <Task>[completed],
            <TodoList>[],
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tasks.mobile.list')), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.mobile.filters')), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
    expect(find.text('今日相关'), findsOneWidget);
    final pendingRow = find.byKey(const ValueKey('tasks.row.31'));
    expect(pendingRow, findsOneWidget);
    expect(tester.getSize(pendingRow).height,
        inInclusiveRange(44, 62));

    await tester.tap(find.byKey(const ValueKey('tasks.mobile.filter.1')));
    await tester.pumpAndSettle();
    expect(find.text('所有任务'), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.row.32')), findsOneWidget);
    final doneRow = find.byKey(const ValueKey('tasks.row.32'));
    expect(tester.getSize(doneRow).height,
        closeTo(tester.getSize(pendingRow).height, 1));
    // The approved mobile row has a round 18dp completed mark, not a
    // rounded-square checkbox. The outer control still owns a 44dp hit area.
    final circles = tester.widgetList<Container>(
      find.descendant(of: doneRow, matching: find.byType(Container)),
    ).where((widget) =>
        widget.decoration is BoxDecoration &&
        (widget.decoration! as BoxDecoration).shape == BoxShape.circle);
    expect(circles, isNotEmpty);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('今天筛选保留全部真实记录，但未完成任务在前', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    Task record(int id, {required bool done}) => Task(
      id: id,
      listId: 1,
      title: '排序任务 $id',
      priority: 'none',
      isCompleted: done,
      createdAt: now,
    );
    final completed = record(1, done: true);
    final firstPending = record(2, done: false);
    final secondPending = record(3, done: false);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(
          dataLoader: () async => <dynamic>[
            <Task>[completed, firstPending, secondPending],
            <Task>[completed, firstPending, secondPending],
            <Task>[completed],
            <TodoList>[],
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('今日相关'), findsOneWidget);
    expect(find.text('3 项'), findsOneWidget);
    final a = find.byKey(const ValueKey('tasks.row.2'));
    final b = find.byKey(const ValueKey('tasks.row.3'));
    final done = find.byKey(const ValueKey('tasks.row.1'));
    expect(a, findsOneWidget);
    expect(b, findsOneWidget);
    expect(done, findsOneWidget);
    expect(tester.getTopLeft(a).dy, lessThan(tester.getTopLeft(b).dy));
    expect(tester.getTopLeft(b).dy, lessThan(tester.getTopLeft(done).dy));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('全部任务混合状态下行高和间距一致，不露出滑动操作背景',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final pending = Task(
      id: 21,
      listId: 1,
      title: '待完成任务',
      priority: 'none',
      isCompleted: false,
      createdAt: now,
    );
    final completed = Task(
      id: 22,
      listId: 1,
      title: '已完成任务',
      priority: 'none',
      isCompleted: true,
      completedAt: now,
      createdAt: now,
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(
          dataLoader: () async => <dynamic>[
            <Task>[pending],
            <Task>[pending, completed],
            <Task>[completed],
            <TodoList>[],
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();

    final pendingRow = find.byKey(const ValueKey('tasks.row.21'));
    final doneRow = find.byKey(const ValueKey('tasks.row.22'));
    expect(pendingRow, findsOneWidget);
    expect(doneRow, findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.swipe.21')), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.swipe.22')), findsNothing);

    final pendingRect = tester.getRect(pendingRow);
    final doneRect = tester.getRect(doneRow);
    expect(pendingRect.height, greaterThanOrEqualTo(44));
    expect(doneRect.height, greaterThanOrEqualTo(44));
    expect(doneRect.height, closeTo(pendingRect.height, 1));
    expect(doneRect.top - pendingRect.bottom,
        closeTo(SlowlightSpacing.xs, 1));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('500 条 Android 任务按需构建，首屏不一次挂载所有滑动行',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final tasks = List<Task>.generate(
      500,
      (index) => Task(
        id: index + 1,
        listId: 1,
        title: '任务 ${index + 1}',
        priority: 'none',
        isCompleted: false,
        createdAt: now,
      ),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(
          dataLoader: () async => <dynamic>[
            tasks,
            tasks,
            <Task>[],
            <TodoList>[],
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byType(SliverList), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.mobile.shell.1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.mobile.shell.500')), findsNothing);
    expect(find.byType(TaskSwipeRow).evaluate().length, lessThan(40));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows 任务详情切换与关闭必须保护未保存草稿', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    Task task(int id, String title) => Task(
      id: id, listId: 1, title: title, priority: 'none',
      isCompleted: false, createdAt: now,
    );
    final first = task(41, '第一项任务');
    final second = task(42, '第二项任务');
    final lists = <TodoList>[
      TodoList(id: 1, name: '收集箱', isInbox: true,
          color: '#8db5a0', createdAt: now),
    ];
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(
          dataLoader: () async => <dynamic>[
            <Task>[first, second],
            <Task>[first, second],
            <Task>[],
            lists,
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tasks.row.41')));
    await tester.pumpAndSettle();
    Finder titleField() => find.descendant(
      of: find.byType(TaskDetailSheet),
      matching: find.byType(EditableText),
    ).first;
    expect(tester.widget<TaskDetailSheet>(find.byType(TaskDetailSheet))
        .task.id, 41);
    await tester.enterText(titleField(), '第一项任务：尚未保存');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('tasks.row.42')));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.widget<TaskDetailSheet>(find.byType(TaskDetailSheet))
        .task.id, 41);
    expect(tester.widget<EditableText>(titleField()).controller.text,
        '第一项任务：尚未保存');

    await tester.tap(find.byKey(const ValueKey('tasks.row.42')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(tester.widget<TaskDetailSheet>(find.byType(TaskDetailSheet))
        .task.id, 42);
    expect(tester.widget<EditableText>(titleField()).controller.text,
        '第二项任务');

    await tester.enterText(titleField(), '第二项任务：草稿');
    await tester.pump();
    await tester.tap(fxTooltipFinder('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsOneWidget);
    await tester.tap(fxTooltipFinder('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows 筛选切换先保护详情草稿，不直接卸载编辑器', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final task = Task(
      id: 81, listId: 1, title: '待处理过滤任务',
      priority: 'none', isCompleted: false, createdAt: now,
    );
    final lists = <TodoList>[
      TodoList(id: 1, name: '收集箱', isInbox: true,
          color: '#8db5a0', createdAt: now),
    ];
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(dataLoader: () async => <dynamic>[
          <Task>[task], <Task>[task], <Task>[], lists,
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tasks.row.81')));
    await tester.pumpAndSettle();
    final editor = find.descendant(
      of: find.byType(TaskDetailSheet),
      matching: find.byType(EditableText),
    ).first;
    await tester.enterText(editor, '尚未保存的任务');
    await tester.pump();

    await tester.tap(find.text('已完成').first);
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsOneWidget);
    expect(tester.widget<EditableText>(editor).controller.text,
        '尚未保存的任务');

    await tester.tap(find.text('已完成').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsNothing);
    expect(find.text('还没有已完成任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows 任务页按原型呈现分栏与轻量详情占位', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final task = Task(id: 221, listId: 1, title: '桌面任务',
        priority: 'none', isCompleted: false, createdAt: now);
    final list = TodoList(id: 1, name: '工作', isInbox: true,
        color: '#8db5a0', createdAt: now);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(dataLoader: () async => <dynamic>[
          <Task>[task], <Task>[task], <Task>[], <TodoList>[list],
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('tasks.row.221'));
    final hint = find.text('选择一项任务查看详情');
    expect(row, findsOneWidget);
    expect(hint, findsOneWidget);
    expect(find.text('列表用于浏览，日期、描述和提醒在这里调整。'),
        findsOneWidget);
    expect(find.text('提示：点击左侧任务即可在当前页面查看详情'),
        findsNothing);
    expect(find.byType(FxCard), findsNothing);
    expect(tester.getTopLeft(hint).dy,
        lessThan(tester.getTopLeft(row).dy + 125));

    await tester.tap(row);
    await tester.pumpAndSettle();
    final detail = find.byType(TaskDetailSheet);
    expect(detail, findsOneWidget);
    expect(tester.widget<TaskDetailSheet>(detail).sidePanel, isTrue);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows 700dp 中等宽度也不全量构建 250 条任务',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final tasks = List<Task>.generate(
      250,
      (index) => Task(
        id: index + 1,
        listId: 1,
        title: '中等宽度任务 ${index + 1}',
        priority: 'none',
        isCompleted: false,
        createdAt: now,
      ),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(
          dataLoader: () async => <dynamic>[
            tasks, tasks, <Task>[], <TodoList>[],
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.row.1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.row.250')), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('任务页 360dp 保持紧凑卡片与可点击任务行', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final task = Task(
      id: 7,
      listId: 1,
      title: '日常阅读',
      priority: 'none',
      isCompleted: false,
      createdAt: DateTime.now(),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskToolScreen(
          dataLoader: () async => <dynamic>[
            <Task>[task],
            <Task>[task],
            <Task>[],
            <TodoList>[],
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final shell = find.byKey(const ValueKey('tasks.mobile.shell.7'));
    expect(shell, findsOneWidget);
    expect(
      tester.getSize(shell).width,
      closeTo(360 - SlowlightSpacing.xxxl * 2, 1),
    );
    final row = find.byKey(const ValueKey('tasks.swipe.7'));
    expect(row, findsOneWidget);
    expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
