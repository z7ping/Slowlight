import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/models/tag.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/repositories/habit_repository.dart';
import 'package:slowlight/repositories/tag_links_repository.dart';
import 'package:slowlight/repositories/tag_repository.dart';
import 'package:slowlight/screens/habit_tool_screen.dart';
import 'package:slowlight/screens/task_create_sheet.dart';
import 'package:slowlight/services/data_service.dart';
import 'package:slowlight/widgets/habit_editor_dialog.dart';

import '../support/fx_test_host.dart';

class _NoTags extends TagRepository {
  @override
  Future<List<Tag>> getTags() async => const [];
}

class _PartialTaskService implements DataService {
  int creates = 0;
  int updates = 0;
  late final created = Task(
    id: 71,
    listId: 1,
    title: '整理资料',
    priority: 'none',
    isCompleted: false,
    createdAt: DateTime(2026),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getLists) {
      return Future<List<TodoList>>.value(const <TodoList>[]);
    }
    if (invocation.memberName == #quickAddToInbox) {
      creates++;
      return Future<Task>.value(created);
    }
    if (invocation.memberName == #updateTask) {
      updates++;
      return updates == 1
          ? Future<Task>.error(StateError('附加属性保存失败'))
          : Future<Task>.value(created);
    }
    return super.noSuchMethod(invocation);
  }
}

class _CountingHabitRepo implements HabitRepository {
  int creates = 0;
  final habits = <Habit>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getAll) {
      return Future<List<Habit>>.value(List<Habit>.from(habits));
    }
    if (invocation.memberName == #create) {
      creates++;
      final created = Habit(
        id: 71,
        userId: 1,
        name: '早起',
        createdAt: DateTime(2026),
      );
      habits.add(created);
      return Future<Habit>.value(created);
    }
    return super.noSuchMethod(invocation);
  }
}

class _FailOnceLinks extends TagLinksRepository {
  int calls = 0;
  @override
  Future<List<Tag>> replaceFor(
    TagLinkedEntity entity, int recordId, List<int> tagIds,
  ) async {
    calls++;
    if (calls == 1) throw StateError('标签关联超时');
    return const [];
  }
}

void main() {
  testWidgets('快捷任务后续保存失败后重试只更新同一条任务', (tester) async {
    final service = _PartialTaskService();
    tester.view.physicalSize = const Size(800, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: SizedBox(
          width: 520,
          height: 640,
          child: TaskCreateSheet(
            quickMode: true,
            desktopDialog: true,
            dataService: service,
            tagRepository: _NoTags(),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.enterText(find.byType(EditableText).first, '整理资料');
    await tester.tap(find.text('添加任务'));
    await tester.pumpAndSettle();
    expect(service.creates, 1);
    expect(service.updates, 1);
    expect(find.textContaining('任务已创建，但其余设置尚未保存'), findsOneWidget);
    await tester.tap(find.text('重试保存其余设置'));
    await tester.pumpAndSettle();
    expect(service.creates, 1);
    expect(service.updates, 2);
    await disposeFxTestHost(tester);
  });

  testWidgets('习惯已创建但标签失败时不重新创建，仅重试标签', (tester) async {
    final habits = _CountingHabitRepo();
    final links = _FailOnceLinks();
    tester.view.physicalSize = const Size(900, 750);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: HabitToolScreen(
          repository: habits,
          tagLinksRepository: links,
          editor: (context, {habit}) async => const HabitEditorValue(
            name: '早起',
            icon: '🌅',
            color: '#fa8c16',
            frequency: 'daily',
            targetDays: 0,
            systemTagId: null,
            tagIds: [101],
            preferredPeriod: '',
            durationMin: 0,
            generateTask: false,
            showCheckinDialog: false,
            specificTime: '',
            reminderAt: {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加习惯'));
    await tester.pumpAndSettle();
    expect(habits.creates, 1);
    expect(links.calls, 1);
    expect(find.textContaining('习惯已创建，但标签保存失败'), findsOneWidget);
    await tester.tap(find.text('重试保存标签'));
    await tester.pumpAndSettle();
    expect(habits.creates, 1);
    expect(links.calls, 2);
    await disposeFxTestHost(tester);
  });
}
