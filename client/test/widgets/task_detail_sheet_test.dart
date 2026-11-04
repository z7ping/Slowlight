import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/tag_picker.dart';
import 'package:slowlight/widgets/task_detail_sheet.dart';

import '../support/fx_test_host.dart';

void main() {
  final task = Task(
    id: 7,
    listId: 1,
    title: '研究课题',
    priority: 'none',
    isCompleted: false,
    systemTagId: 3,
    createdAt: DateTime(2026, 10, 16),
  );
  final lists = [
    TodoList(
      id: 1,
      name: '工作',
      color: '#1890ff',
      createdAt: DateTime(2026, 10, 16),
    ),
  ];

  testWidgets('Android 任务详情显示核心属性，使用同一 Sheet 内的编辑视图',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskDetailSheet(
          task: task,
          lists: lists,
          onChanged: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('任务详情'), findsOneWidget);
    expect(find.byKey(const ValueKey('task.detail.title')), findsOneWidget);
    expect(find.byKey(const ValueKey('task.detail.property.list')), findsOneWidget);
    expect(find.byKey(const ValueKey('task.detail.property.due')), findsOneWidget);
    expect(find.byKey(const ValueKey('task.detail.property.priority')), findsOneWidget);
    expect(find.byKey(const ValueKey('task.detail.property.repeat')), findsOneWidget);
    expect(find.text('时间安排'), findsNothing);
    expect(find.byType(TagPicker), findsNothing);
    expect(find.text('历史分类（兼容）'), findsNothing);
    expect(find.text('保存修改'), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('task.detail.property.priority')));
    await tester.pumpAndSettle();
    expect(find.text('设置优先级'), findsOneWidget);
    expect(find.text('高'), findsOneWidget);
    await tester.tap(find.text('高'));
    await tester.pumpAndSettle();
    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('有未保存的修改'), findsOneWidget);
    final save = tester.widget<FxButton>(
        find.byKey(const ValueKey('task.detail.primaryAction')));
    expect(save.onPressed, isNotNull);

    await tester.ensureVisible(find.byKey(const ValueKey('task.detail.moreSettings')));
    await tester.tap(find.byKey(const ValueKey('task.detail.moreSettings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task.detail.property.tags')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('task.detail.property.tags')));
    await tester.tap(find.byKey(const ValueKey('task.detail.property.tags')));
    await tester.pumpAndSettle();
    expect(find.byType(TagPicker), findsOneWidget);
    expect(find.text('历史分类（兼容）'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 重复属性支持每周选日且不立即保存',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskDetailSheet(task: task, lists: lists, onChanged: () {}),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task.detail.property.repeat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每周'));
    await tester.pumpAndSettle();
    expect(find.text('选择星期'), findsOneWidget);
    expect(find.byType(FxChoiceChip), findsNWidgets(7));
    expect(find.text('修改后返回详情'), findsOneWidget);
    expect(find.text('有未保存的修改'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('task.detail.primaryAction')));
    await tester.pumpAndSettle();
    expect(find.text('有未保存的修改'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('Android 360dp 大字号 $scale 下核心属性与底部保存可达',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(360, 880);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildFxTestHost(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: TaskDetailSheet(
            task: task,
            lists: lists,
            onChanged: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('task.detail.property.list')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('task.detail.primaryAction')),
          findsOneWidget);
      final save = find.byKey(const ValueKey('task.detail.primaryAction'));
      expect(tester.getSize(save).height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }

  testWidgets('Windows 任务详情保留紧凑右侧面板操作区', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 720,
          child: TaskDetailSheet(
            task: task,
            lists: lists,
            sidePanel: true,
            onChanged: () {},
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byType(FxMenu<String>), findsNothing);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('保存修改'), findsOneWidget);
    expect(find.text('历史分类（兼容）'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
