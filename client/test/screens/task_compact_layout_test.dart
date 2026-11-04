import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/task_tool_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
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

    final cards = tester.widgetList<FxCard>(find.byType(FxCard)).toList();
    expect(cards, isNotEmpty);
    expect(
      cards.first.padding!.resolve(TextDirection.ltr).top,
      lessThanOrEqualTo(12),
    );
    final row = find.byKey(const ValueKey('tasks.swipe.7'));
    expect(row, findsOneWidget);
    expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
