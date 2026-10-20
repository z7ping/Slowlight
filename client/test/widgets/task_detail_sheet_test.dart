import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/observation_tag.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/repositories/observation_tag_repository.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/task_detail_sheet.dart';
import 'package:slowlight/widgets/tag_picker.dart';

import '../support/fx_test_host.dart';

class _FakeTags extends ObservationTagRepository {
  @override
  Future<List<ObservationTag>> getAll() async => [
        const ObservationTag(
          id: 3,
          name: '专题研究',
          icon: '🔖',
          color: '#1890ff',
          dimensionKey: 'cognition',
        ),
      ];
}

void main() {
  testWidgets('04 任务详情使用统一标签选择器、四级优先级和年度重复', (tester) async {
    tester.view.physicalSize = const Size(360, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskDetailSheet(
          task: task,
          lists: lists,
          onChanged: () {},
          tagsRepository: _FakeTags(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final labels = find.byType(TagPicker);
    expect(labels, findsOneWidget);
    // 原 system_tag_id 仍存于历史兼容字段，不混用 canonical tag IDs。
    expect(tester.widget<TagPicker>(labels).selectedTags, isEmpty);
    expect(find.text('无'), findsOneWidget);
    final selects = tester.widgetList<FxSelect<String>>(find.byType(FxSelect<String>));
    expect(
      selects.any((widget) => widget.options.any((o) => o.value == 'yearly')),
      isTrue,
    );

    expect(task.systemTagId, 3);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
