import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/list_manage_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

TodoList _list() => TodoList(
  id: 10,
  name: '客户清单',
  icon: '📁',
  color: '#1890FF',
  createdAt: DateTime(2026, 11, 1),
);

Task _task() => Task(
  id: 18,
  listId: 10,
  title: '已保存的任务',
  priority: 'none',
  isCompleted: false,
  createdAt: DateTime(2026, 11, 1),
);

void main() {
  testWidgets('P14 任务统计挂起时清单仍可浏览和创建', (tester) async {
    final pending = Completer<List<Task>>();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: ListManageScreen(
        listsLoader: () async => [_list()],
        tasksLoader: () => pending.future,
      )),
    ));
    await tester.pumpAndSettle();
    expect(pending.isCompleted, isFalse);
    expect(find.text('客户清单'), findsOneWidget);
    expect(find.text('— 条'), findsOneWidget);
    expect(find.text('新建清单'), findsOneWidget);
    expect(find.byType(FxCircularProgress), findsNothing);

    pending.complete([_task()]);
    await tester.pumpAndSettle();
    expect(find.text('1 条'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P14 任务数失败不会隐藏清单，重试成功再显示真实数量',
      (tester) async {
    var tasksRead = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: ListManageScreen(
        listsLoader: () async => [_list()],
        tasksLoader: () async {
          if (++tasksRead == 1) throw StateError('count source offline');
          return [_task()];
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('客户清单'), findsOneWidget);
    expect(find.text('— 条'), findsOneWidget);
    expect(find.textContaining('任务数量未确认'), findsOneWidget);
    expect(find.text('1 条'), findsNothing);

    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(tasksRead, 2);
    expect(find.text('客户清单'), findsOneWidget);
    expect(find.text('1 条'), findsOneWidget);
    expect(find.textContaining('任务数量未确认'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P14 清单读取失败时不会把失败当作空清单', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: ListManageScreen(
        listsLoader: () async => throw StateError('lists offline'),
        tasksLoader: () async => <Task>[],
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('清单加载失败'), findsOneWidget);
    expect(find.text('还没有清单'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
