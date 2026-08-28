import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/widgets/task_tile.dart';
import 'package:slowlight/models/task.dart';

void main() {
  Task makeTask({
    int id = 1,
    String title = '测试任务',
    String priority = 'none',
    bool isCompleted = false,
    DateTime? dueDate,
    String? dueTime,
  }) {
    return Task(
      id: id,
      listId: 1,
      title: title,
      priority: priority,
      isCompleted: isCompleted,
      dueDate: dueDate,
      dueTime: dueTime,
      createdAt: DateTime(2026),
    );
  }

  group('TaskTile', () {
    group('基本渲染', () {
      testWidgets('显示任务标题', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TaskTile(
              task: makeTask(title: '买牛奶'),
              onToggle: () {},
              onDelete: () {},
            ),
          ),
        ));

        expect(find.text('买牛奶'), findsOneWidget);
      });

      testWidgets('显示 Checkbox', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TaskTile(
              task: makeTask(),
              onToggle: () {},
              onDelete: () {},
            ),
          ),
        ));

        expect(find.byType(Checkbox), findsOneWidget);
      });

      testWidgets('已完成任务 checkbox 为选中状态', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TaskTile(
              task: makeTask(isCompleted: true),
              onToggle: () {},
              onDelete: () {},
            ),
          ),
        ));

        final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
        expect(checkbox.value, true);
      });

      testWidgets('未完成任务 checkbox 为未选中状态', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TaskTile(
              task: makeTask(isCompleted: false),
              onToggle: () {},
              onDelete: () {},
            ),
          ),
        ));

        final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
        expect(checkbox.value, false);
      });
    });

    group('优先级', () {
      testWidgets('high 优先级显示竖条', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TaskTile(
              task: makeTask(priority: 'high'),
              onToggle: () {},
              onDelete: () {},
            ),
          ),
        ));

        expect(find.byType(TaskTile), findsOneWidget);
      });

      testWidgets('不同优先级渲染不同颜色竖条', (tester) async {
        for (final priority in ['none', 'low', 'medium', 'high']) {
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: TaskTile(
                task: makeTask(priority: priority, id: priority.hashCode),
                onToggle: () {},
                onDelete: () {},
              ),
            ),
          ));
          expect(find.byType(TaskTile), findsOneWidget);
        }
      });
    });

    group('截止日期', () {
      testWidgets('今天显示"今天"', (tester) async {
        final now = DateTime.now();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TaskTile(
              task: makeTask(dueDate: DateTime(now.year, now.month, now.day)),
              onToggle: () {},
              onDelete: () {},
            ),
          ),
        ));

        expect(find.text('今天'), findsOneWidget);
      });

      testWidgets('明天显示"明天"', (tester) async {
        final now = DateTime.now();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TaskTile(
              task: makeTask(dueDate: DateTime(now.year, now.month, now.day + 1)),
              onToggle: () {},
              onDelete: () {},
            ),
          ),
        ));

        expect(find.text('明天'), findsOneWidget);
      });

      testWidgets('无截止日期不显示日期文字', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TaskTile(
              task: makeTask(dueDate: null),
              onToggle: () {},
              onDelete: () {},
            ),
          ),
        ));

        expect(find.text('今天'), findsNothing);
        expect(find.text('明天'), findsNothing);
      });
    });

    group('交互', () {
      testWidgets('点击 Checkbox 触发 onToggle', (tester) async {
        bool toggled = false;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TaskTile(
              task: makeTask(),
              onToggle: () => toggled = true,
              onDelete: () {},
            ),
          ),
        ));

        await tester.tap(find.byType(Checkbox));
        expect(toggled, true);
      });

      testWidgets('点击卡片触发 onTap', (tester) async {
        bool tapped = false;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TaskTile(
              task: makeTask(),
              onToggle: () {},
              onDelete: () {},
              onTap: () => tapped = true,
            ),
          ),
        ));

        await tester.tap(find.text('测试任务'));
        expect(tapped, true);
      });
    });
  });
}
