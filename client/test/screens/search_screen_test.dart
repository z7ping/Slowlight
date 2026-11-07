import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/models/reflection_entry.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/search_screen.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('P09 搜索观察/回应结果分别传递原始记录', (tester) async {
    final observation = ReflectionEntry(
      id: 912,
      entryType: 'observation',
      content: '观察今天的工作节奏',
      createdAt: DateTime(2026, 10, 28, 14, 35),
    );
    final response = ReflectionEntry(
      id: 913,
      entryType: 'reflection',
      content: '观察后决定提前休息',
      createdAt: DateTime(2026, 10, 28, 15),
    );
    final selected = <ReflectionEntry>[];
    await tester.pumpWidget(buildFxTestHost(
      home: SearchScreen(
        dataLoader: (_) async => (
          tasks: <Task>[],
          habits: <Habit>[],
          reflections: [observation, response],
          lists: <TodoList>[],
        ),
        onOpenReflection: selected.add,
      ),
    ));
    await tester.pump();
    await tester.enterText(find.byType(EditableText).first, '观察');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    await tester.tap(find.text('观察今天的工作节奏'));
    await tester.tap(find.text('观察后决定提前休息'));
    expect(selected.map((entry) => entry.id), [912, 913]);
    expect(selected.first.entryType, 'observation');
    expect(selected.last.entryType, 'reflection');
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P09 搜索习惯命中通过唯一正式入口打开指定习惯', (tester) async {
    final habit = Habit(
      id: 86,
      userId: 1,
      name: '晨间阅读',
      createdAt: DateTime(2026, 11, 7),
    );
    int? selectedHabitId;
    await tester.pumpWidget(buildFxTestHost(
      home: SearchScreen(
        dataLoader: (_) async => (
          tasks: <Task>[],
          habits: <Habit>[habit],
          reflections: <ReflectionEntry>[],
          lists: <TodoList>[],
        ),
        onOpenHabit: (selected) => selectedHabitId = selected.id,
      ),
    ));
    await tester.pump();
    await tester.enterText(find.byType(EditableText).first, '晨间阅读');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    await tester.tap(find.text('晨间阅读'));
    expect(selectedHabitId, 86);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P09 一个搜索来源失败仍展示其他真实任务结果', (tester) async {
    final task = Task(
      id: 71,
      listId: 1,
      title: '待处理的取回任务',
      priority: 'none',
      isCompleted: false,
      createdAt: DateTime.now(),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: SearchScreen(
        sourceLoaders: (
          tasks: (_) async => [task],
          habits: () async => throw StateError('习惯来源临时失败'),
          reflections: () async => <ReflectionEntry>[],
          lists: () async => <TodoList>[],
        ),
      ),
    ));
    await tester.pump();
    await tester.enterText(find.byType(EditableText).first, '取回任务');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('待处理的取回任务'), findsOneWidget);
    expect(find.textContaining('部分搜索来源未读取：习惯'), findsOneWidget);
    expect(find.text('搜索暂时不可用'), findsNothing);
    expect(find.text('没有找到相关内容'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P09 部分来源未确认且没有匹配结果不显示完整空结果', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: SearchScreen(
        sourceLoaders: (
          tasks: (_) async => throw StateError('任务来源失败'),
          habits: () async => <Habit>[],
          reflections: () async => <ReflectionEntry>[],
          lists: () async => <TodoList>[],
        ),
      ),
    ));
    await tester.pump();
    await tester.enterText(find.byType(EditableText).first, '测试关键词');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('已读取来源没有匹配结果'), findsOneWidget);
    expect(find.text('没有找到相关内容'), findsNothing);
    expect(find.textContaining('部分搜索来源未读取：任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P09 输入新关键词后，上一查询在防抖期间返回也不得显示旧结果', (tester) async {
    final pending = Completer<SearchResultData>();
    Task task(int id, String title) => Task(
      id: id,
      listId: 1,
      title: title,
      priority: 'none',
      isCompleted: false,
      createdAt: DateTime.now(),
    );
    SearchResultData values(List<Task> tasks) => (
      tasks: tasks,
      habits: <Habit>[],
      reflections: <ReflectionEntry>[],
      lists: <TodoList>[],
    );
    await tester.pumpWidget(buildFxTestHost(
      home: SearchScreen(
        dataLoader: (query) =>
            query == '旧关键词'
                ? pending.future
                : Future.value(values([task(2, '新结果')])),
      ),
    ));
    await tester.pump();
    await tester.enterText(find.byType(EditableText).first, '旧关键词');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(EditableText).first, '新关键词');
    await tester.pump(const Duration(milliseconds: 50));
    pending.complete(values([task(1, '旧结果')]));
    await tester.pump();
    expect(find.text('旧结果'), findsNothing);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('新结果'), findsOneWidget);
    expect(find.text('旧结果'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('02 查询失败展示重试，成功空结果才显示无记录', (tester) async {
    var attempts = 0;
    Future<SearchResultData> loader(String query) async {
      attempts++;
      if (attempts == 1) throw StateError('data source unavailable');
      return (
        tasks: <Task>[],
        habits: <Habit>[],
        reflections: <ReflectionEntry>[],
        lists: <TodoList>[],
      );
    }

    await tester.pumpWidget(
      buildFxTestHost(
        home: SearchScreen(dataLoader: loader),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(EditableText).first, '不存在的任务');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('搜索暂时不可用'), findsOneWidget);
    expect(find.text('没有找到相关内容'), findsNothing);
    await tester.tap(find.text('重试搜索'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('搜索暂时不可用'), findsNothing);
    expect(find.text('没有找到相关内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
