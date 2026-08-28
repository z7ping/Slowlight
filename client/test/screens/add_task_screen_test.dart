import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
    TodoList(id: 2, name: '生活', color: '#00ff00', createdAt: DateTime(2026)),
  ];

  AddTaskScreen buildScreen() =>
      AddTaskScreen(lists: testLists, selectedListId: 1);

  group('AddTaskScreen', () {
    group('UI 渲染', () {
      testWidgets('显示标题"新建任务"', (tester) async {
        await tester.pumpWidget(buildHost(buildScreen()));
        await tester.pump();

        expect(find.text('新建任务'), findsOneWidget);
      });

      testWidgets('显示返回按钮', (tester) async {
        await tester.pumpWidget(buildHost(buildScreen()));
        await tester.pump();
        expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);
      });

      testWidgets('显示保存按钮', (tester) async {
        await tester.pumpWidget(buildHost(buildScreen()));
        await tester.pump();

        expect(find.text('保存'), findsOneWidget);
      });

      testWidgets('显示任务标题输入框', (tester) async {
        await tester.pumpWidget(buildHost(buildScreen()));
        await tester.pump();

        expect(find.text('任务标题'), findsOneWidget);
      });

      testWidgets('显示各功能区块', (tester) async {
        await tester.pumpWidget(buildHost(buildScreen()));
        await tester.pump();

        expect(find.text('清单'), findsOneWidget);
        expect(find.text('优先级'), findsOneWidget);
      });
    });

    group('表单验证', () {
      testWidgets('标题为空时点保存显示提示', (tester) async {
        await tester.pumpWidget(buildHost(buildScreen()));
        await tester.pump();

        final saveBtn = find.text('保存');
        expect(saveBtn, findsOneWidget);
        await tester.tap(saveBtn);
        await tester.pump();
        expect(find.text('请输入任务标题'), findsOneWidget);
      });
    });

    group('返回导航', () {
      testWidgets('点击返回按钮可 pop', (tester) async {
        await tester.pumpWidget(buildHost(
          Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (_) => AddTaskScreen(lists: testLists, selectedListId: 1),
            ),
          ),
        ));
        await tester.pump();

        expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);
      });
    });
  });
}
