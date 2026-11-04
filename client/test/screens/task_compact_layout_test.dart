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
      for (final field in ['list', 'due', 'priority', 'repeat']) {
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
    expect(find.text('待处理'), findsOneWidget);
    final pendingRow = find.byKey(const ValueKey('tasks.row.31'));
    expect(pendingRow, findsOneWidget);
    expect(tester.getSize(pendingRow).height,
        inInclusiveRange(60, 110));

    await tester.tap(find.byKey(const ValueKey('tasks.mobile.filter.1')));
    await tester.pumpAndSettle();
    expect(find.text('所有任务'), findsOneWidget);
    expect(find.byKey(const ValueKey('tasks.row.32')), findsOneWidget);
    final doneRow = find.byKey(const ValueKey('tasks.row.32'));
    expect(tester.getSize(doneRow).height,
        closeTo(tester.getSize(pendingRow).height, 1));
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
