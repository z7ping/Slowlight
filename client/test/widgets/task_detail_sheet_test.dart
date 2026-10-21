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

  testWidgets('Android 任务详情按创建任务字段顺序展示，隐藏兼容分类', (tester) async {
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
    await tester.pump();

    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('清单'), findsOneWidget);
    expect(find.text('优先级'), findsOneWidget);
    expect(find.text('时间安排'), findsOneWidget);
    expect(find.text('到期日期'), findsOneWidget);
    expect(find.text('重复'), findsOneWidget);
    expect(find.byType(TagPicker), findsOneWidget);
    expect(tester.widget<TagPicker>(find.byType(TagPicker)).label, '标签');
    expect(find.text('历史分类（兼容）'), findsNothing);
    expect(find.text('归属维度（可选）'), findsNothing);

    final chips = tester.widgetList<FxChoiceChip>(find.byType(FxChoiceChip));
    expect(chips.any((chip) => chip.label == '无' && chip.selected), isTrue);
    expect(chips.any((chip) => chip.label == '高'), isTrue);
    expect(chips.any((chip) => chip.label == '中'), isTrue);
    expect(chips.any((chip) => chip.label == '低'), isTrue);
    final selects = tester.widgetList<FxSelect<String>>(
      find.byType(FxSelect<String>),
    );
    expect(selects.any((widget) =>
      widget.options.any((option) => option.value == 'yearly')), isTrue);
    expect(find.byType(FxMenu<String>), findsOneWidget);
    expect(find.text('删除'), findsNothing);
    expect(find.text('保存修改'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

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
