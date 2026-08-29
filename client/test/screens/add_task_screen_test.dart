import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/add_task_screen.dart';
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

  AddTaskScreen buildScreen() =>
      AddTaskScreen(lists: testLists, selectedListId: 1);

  group('AddTaskScreen 稳定契约', () {
    testWidgets('空标题提交会被校验拦截', (tester) async {
      await tester.pumpWidget(buildHost(buildScreen()));
      await tester.pump();

      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(AddTaskScreen), findsOneWidget);
    });

    testWidgets('窄屏表单不产生布局异常', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildHost(buildScreen()));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
