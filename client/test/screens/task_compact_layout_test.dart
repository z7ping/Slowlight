import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/task_tool_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
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
