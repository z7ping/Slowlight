import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/quadrant_screen.dart';

import '../support/fx_test_host.dart';

Task _task(int id, String title, String priority) => Task(
      id: id,
      listId: 1,
      title: title,
      priority: priority,
      isCompleted: false,
      createdAt: DateTime(2026, 10, 16),
    );

Future<QuadrantData> _loadTasks(List<Task> tasks) async => (
      tasks: tasks,
      lists: [
        TodoList(
          id: 1,
          name: '工作',
          color: '#1890ff',
          createdAt: DateTime(2026, 10, 16),
        ),
      ],
    );

void main() {
  testWidgets('Android 360dp 沿用 2×2 四象限且 none 是不重要不紧急', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: QuadrantScreen(
          dataLoader: () => _loadTasks([_task(7, '传智面试录课', 'none')]),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byType(GridView).first);
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      2,
    );
    expect(find.text('不重要 · 不紧急'), findsOneWidget);
    expect(find.text('未设优先级'), findsNothing);
    expect(find.text('传智面试录课'), findsOneWidget);
    expect(fxTooltipFinder('移动到其他象限'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 多于两条可查看全部，第三条没有丢失', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: QuadrantScreen(
          dataLoader: () => _loadTasks([
            _task(1, '第一条', 'urgent_important'),
            _task(2, '第二条', 'urgent_important'),
            _task(3, '第三条', 'urgent_important'),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('查看全部（3）'), findsOneWidget);
    expect(find.text('第三条'), findsNothing);
    await tester.tap(find.text('查看全部（3）'));
    await tester.pumpAndSettle();
    expect(find.text('第三条'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 大字体窄屏退化为单列完整象限', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.35),
          ),
          child: QuadrantScreen(dataLoader: () => _loadTasks([])),
        )),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('四象限读取失败时显示可重试错误，而不是四个空象限', (tester) async {
    var attempts = 0;
    Future<QuadrantData> load() async {
      attempts++;
      if (attempts == 1) throw StateError('offline');
      return _loadTasks([]);
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
    expect(find.text('不重要 · 不紧急'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
