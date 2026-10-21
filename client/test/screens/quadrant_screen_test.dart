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

    // 第四个象限通常在 360dp 首屏以下，需要先滚动进入可见范围。
    await tester.scrollUntilVisible(
      find.text('未设优先级'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('未设优先级'), findsOneWidget);
    expect(find.text('不重要 · 不紧急'), findsNothing);
    expect(fxTooltipFinder('移动到其他象限'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
  testWidgets('四象限读取失败时显示可重试错误，而不是四个空象限', (tester) async {
    var attempts = 0;
    Future<QuadrantData> load() async {
      attempts++;
      if (attempts == 1) throw StateError('offline');
      return (tasks: <Task>[], lists: <TodoList>[]);
    }

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: QuadrantScreen(dataLoader: load)),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('quadrant-load-error')), findsOneWidget);
    expect(find.text('暂时无法加载四象限'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byKey(const ValueKey('quadrant-load-error')), findsNothing);
    expect(find.text('未设优先级'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
