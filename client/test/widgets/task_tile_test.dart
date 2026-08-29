import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/widgets/task_tile.dart';
import 'package:slowlight/models/task.dart';

void main() {
  Task makeTask({
    String title = '测试任务',
    bool isCompleted = false,
  }) {
    return Task(
      id: 1,
      listId: 1,
      title: title,
      priority: 'none',
      isCompleted: isCompleted,
      createdAt: DateTime(2026),
    );
  }

  Widget host(
    Task task, {
    required VoidCallback onToggle,
    VoidCallback? onTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TaskTile(
          task: task,
          onToggle: onToggle,
          onDelete: () {},
          onTap: onTap,
        ),
      ),
    );
  }

  group('TaskTile 稳定契约', () {
    testWidgets('展示用户任务数据并映射完成状态', (tester) async {
      await tester.pumpWidget(
        host(makeTask(title: '买牛奶', isCompleted: true), onToggle: () {}),
      );

      expect(find.text('买牛奶'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    });

    testWidgets('点击完成控件触发状态切换回调', (tester) async {
      var toggled = false;
      await tester.pumpWidget(
        host(makeTask(), onToggle: () => toggled = true),
      );

      await tester.tap(find.byType(Checkbox));

      expect(toggled, isTrue);
    });

    testWidgets('点击任务主体触发打开回调', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        host(
          makeTask(),
          onToggle: () {},
          onTap: () => tapped = true,
        ),
      );

      await tester.tap(find.text('测试任务'));

      expect(tapped, isTrue);
    });
  });
}
