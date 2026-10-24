import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/task_tool_screen.dart';
import 'package:slowlight/widgets/task_detail_sheet.dart';

import '../support/fx_test_host.dart';

void main() {
  test('旧首页、侧栏与维度字段不得悄悄重返正式业务调用链', () async {
    const compatibilityFiles = {
      'lib/screens/home_drawer.dart': 'HomeDrawer',
      'lib/screens/home_today_body.dart': 'HomeTodayBody',
      'lib/widgets/task_dimension_field.dart': 'TaskDimensionField',
    };
    final usage = <String>[];
    await for (final entry in Directory('lib').list(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('.dart')) continue;
      final name = entry.path.replaceAll('\\', '/');
      if (compatibilityFiles.containsKey(name)) continue;
      final source = await entry.readAsString();
      for (final symbol in compatibilityFiles.values) {
        if (RegExp('\\b$symbol\\b').hasMatch(source)) {
          usage.add('$name: $symbol');
        }
      }
    }
    expect(
      usage,
      isEmpty,
      reason: '非活动兼容文件仅保留历史兼容，不得以第二套正式 UI 重新引入',
    );
  });

  testWidgets('桌面选择任务后在原工作区查看详情，关闭后保留列表', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final task = Task(
      id: 1, listId: 1, title: '待查看的任务', priority: 'none',
      isCompleted: false, createdAt: DateTime(2026, 10, 24),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskToolScreen(dataLoader: () async => <dynamic>[
        <Task>[task], <Task>[task], <Task>[], <TodoList>[],
      ])),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(task.title).first);
    // 详情立即可用；标签的独立异步加载不应成为选中任务的等待条件。
    await tester.pump();
    final detail = find.byType(TaskDetailSheet);
    expect(detail, findsOneWidget);
    expect(tester.widget<TaskDetailSheet>(detail).sidePanel, isTrue);
    expect(find.ancestor(of: detail, matching: find.byType(TaskToolScreen)),
        findsOneWidget);
    tester.widget<TaskDetailSheet>(detail).onClose!();
    await tester.pumpAndSettle();
    expect(detail, findsNothing);
    expect(find.text(task.title), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
