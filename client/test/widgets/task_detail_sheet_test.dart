import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/widgets/task_detail_sheet.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/ui/theme_manager.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget buildHost(Widget home) {
  return ShadTheme(
    data: ThemeManager.shadLight,
    child: MaterialApp(
      theme: ThemeManager.lightTheme,
      home: home,
    ),
  );
}

void main() {
  final testLists = [
    TodoList(id: 1, name: '工作', color: '#ff0000', createdAt: DateTime(2026)),
  ];

  final testTask = Task(
    id: 1,
    listId: 1,
    title: '测试任务',
    priority: 'medium',
    isCompleted: false,
    createdAt: DateTime(2026),
  );

  Widget openTrigger() => Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => TaskDetailSheet.show(
              context,
              task: testTask,
              lists: testLists,
              onChanged: () {},
            ),
            child: const Text('打开'),
          ),
        ),
      );

  group('TaskDetailSheet', () {
    testWidgets('弹窗渲染不崩溃', (tester) async {
      await tester.pumpWidget(buildHost(openTrigger()));

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('测试任务'), findsOneWidget);
    });

    testWidgets('显示优先级标签', (tester) async {
      await tester.pumpWidget(buildHost(openTrigger()));

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('优先级'), findsOneWidget);
    });
  });
}
