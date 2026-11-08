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

  testWidgets('删除前重新核对任务范围并展示全部影响，取消不删除',
      (tester) async {
    var reads = 0;
    final completed = Task(
      id: 19,
      listId: 10,
      title: '已完成的提交',
      priority: 'none',
      isCompleted: true,
      createdAt: DateTime(2026, 11, 1),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: ListManageScreen(
        listsLoader: () async => [_list()],
        tasksLoader: () async {
          reads++;
          return [_task(), completed];
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(reads, 1);

    await tester.tap(find.byWidgetPredicate(
      (widget) => widget is FxIconButton && widget.tooltip == '删除',
    ));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('删除清单及其任务？'), findsOneWidget);
    expect(find.textContaining('同时删除 2 项任务'), findsOneWidget);
    expect(find.textContaining('已完成 1 项'), findsOneWidget);
    expect(find.text('已保存的任务 · 未完成'), findsOneWidget);
    expect(find.text('已完成的提交 · 已完成'), findsOneWidget);
    expect(find.byKey(const ValueKey('lists.delete.affectedTasks')),
        findsOneWidget);
    await tester.tap(find.text('保留清单'));
    await tester.pumpAndSettle();
    expect(find.text('客户清单'), findsOneWidget);
    expect(find.text('删除清单及其任务？'), findsNothing);
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
  testWidgets('P14 点击清单整行打开任务详情，编辑沿用已有编辑器',
      (tester) async {
    tester.view.physicalSize = const Size(950, 1250);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: ListManageScreen(
        listsLoader: () async => [_list()],
        tasksLoader: () async => [_task()],
      )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('客户清单'));
    await tester.pumpAndSettle();
    expect(find.text('1 条任务'), findsOneWidget);
    expect(find.text('已保存的任务'), findsOneWidget);
    expect(find.byKey(const ValueKey('lists.detail.tasks')), findsOneWidget);

    await tester.tap(find.text('编辑清单'));
    await tester.pumpAndSettle();
    expect(find.text('编辑清单'), findsOneWidget);
    expect(find.byType(FxInput), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P14 任务数未确认时清单详情不显示旧任务或误报空', (tester) async {
    tester.view.physicalSize = const Size(950, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pending = Completer<List<Task>>();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: ListManageScreen(
        listsLoader: () async => [_list()],
        tasksLoader: () => pending.future,
      )),
    ));
    await tester.pump();
    await tester.tap(find.text('客户清单'));
    await tester.pumpAndSettle();
    expect(find.text('任务数量待核对'), findsOneWidget);
    expect(find.text('暂无任务'), findsNothing);
    expect(find.text('已保存的任务'), findsNothing);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    pending.complete([_task()]);
    await tester.pumpAndSettle();
    expect(find.text('1 条'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P14 默认收集箱可看详情但禁止编辑/删除', (tester) async {
    tester.view.physicalSize = const Size(950, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final inbox = TodoList(
      id: 2, name: '收集箱', icon: '📥', isInbox: true,
      createdAt: DateTime(2026, 11, 1),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: ListManageScreen(
        listsLoader: () async => [inbox],
        tasksLoader: () async => <Task>[],
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate(
        (widget) => widget is FxIconButton && widget.tooltip == '编辑'),
        findsNothing);
    expect(find.byWidgetPredicate(
        (widget) => widget is FxIconButton && widget.tooltip == '删除'),
        findsNothing);
    await tester.tap(find.text('收集箱'));
    await tester.pumpAndSettle();
    expect(find.text('暂无任务'), findsOneWidget);
    expect(find.text('编辑清单'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
