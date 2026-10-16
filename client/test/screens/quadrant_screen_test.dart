import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/quadrant_screen.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('05 Android 未设置优先级不被当成不重要，提供显式移动入口', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<QuadrantData> load() async => (
      tasks: [
        Task(
          id: 7,
          listId: 1,
          title: '尚未评估的任务',
          priority: 'none',
          isCompleted: false,
          createdAt: DateTime(2026, 10, 16),
        ),
      ],
      lists: [
        TodoList(
          id: 1,
          name: '工作',
          color: '#1890ff',
          createdAt: DateTime(2026, 10, 16),
        ),
      ],
    );

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: QuadrantScreen(dataLoader: load)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('未设优先级'), findsOneWidget);
    expect(find.text('不重要 · 不紧急'), findsNothing);
    expect(fxTooltipFinder('移动到其他象限'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
