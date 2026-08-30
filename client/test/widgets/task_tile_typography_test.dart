import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/ui/app_theme.dart';
import 'package:slowlight/ui/typography_tokens.dart';
import 'package:slowlight/widgets/task_tile.dart';

void main() {
  Task buildTask() => Task(
        id: 1,
        listId: 1,
        title: '这是一个用于验证大字体布局的较长任务标题',
        priority: 'none',
        isCompleted: false,
        createdAt: DateTime(2026, 8, 30),
      );

  Widget host(Widget child) => ShadTheme(
        data: shadLightTheme(null),
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: child,
        ),
      );

  testWidgets('TaskTile 紧凑模式在 360dp + 200% 字体缩放下允许标题换行',
      (tester) async {
    await tester.pumpWidget(
      host(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: TaskTile(
              task: buildTask(),
              compact: true,
              onToggle: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(
      find.text('这是一个用于验证大字体布局的较长任务标题'),
    );
    expect(title.style?.fontSize, SlowlightTypography.bodySize);
    expect(title.maxLines, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TaskTile 默认字号仍保持紧凑标题单行', (tester) async {
    await tester.pumpWidget(
      host(
        Scaffold(
          body: TaskTile(
            task: buildTask(),
            compact: true,
            onToggle: () {},
            onDelete: () {},
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(
      find.text('这是一个用于验证大字体布局的较长任务标题'),
    );
    expect(title.style?.fontSize, SlowlightTypography.bodySize);
    expect(title.maxLines, 1);
  });
}
