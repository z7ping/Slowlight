import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/models/reflection_entry.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/search_screen.dart';

import '../support/fx_test_host.dart';

void main() {
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
