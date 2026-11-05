import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/inbox_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('收集箱未知创建结果保留标题，成功后才清空输入',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var submissions = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: InboxScreen(
        dataLoader: () async => (
          tasks: <Task>[],
          lists: <TodoList>[],
        ),
        createTask: (title) async {
          submissions++;
          if (submissions == 1) throw StateError('unknown result');
          return Task(
            id: 7,
            listId: 1,
            title: title,
            priority: 'none',
            isCompleted: false,
            createdAt: DateTime(2026, 11, 5),
          );
        },
      ),
    ));
    await tester.pumpAndSettle();

    final edit = find.byType(EditableText).first;
    await tester.enterText(edit, '不要丢失的想法');
    await tester.tap(find.widgetWithText(FxButton, '添加'));
    await tester.pumpAndSettle();

    expect(submissions, 1);
    expect(tester.widget<EditableText>(edit).controller.text,
        '不要丢失的想法');
    expect(find.text('添加'), findsOneWidget);

    await tester.tap(find.widgetWithText(FxButton, '添加'));
    await tester.pumpAndSettle();
    expect(submissions, 2);
    expect(tester.widget<EditableText>(edit).controller.text, isEmpty);
    expect(find.text('不要丢失的想法'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
