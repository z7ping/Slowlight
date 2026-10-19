import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/add_task_screen.dart';
import 'package:slowlight/screens/task_create_sheet.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('Android 平板宽度超过 600dp 仍进入完整任务页面而非桌面弹窗', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(840, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final lists = [
      TodoList(id: 1, name: '工作', color: '#3B82F6', createdAt: DateTime(2026)),
    ];
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              TaskCreateSheet.showFullCreate(context, lists: lists);
            },
            child: const Text('打开完整表单'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开完整表单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AddTaskScreen), findsOneWidget);
    expect(tester.widget<AddTaskScreen>(find.byType(AddTaskScreen)).embedded, isFalse);
    expect(find.text('新建任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  group('TaskCreateSheet', () {
    test('快速创建默认使用无优先级并安排到今天', () {
      const sheet = TaskCreateSheet(quickMode: true);

      expect(sheet.initialPriority, 'none');
      expect(sheet.defaultDueToday, isTrue);
    });

    test('四象限入口可以预设优先级且不强制安排到今天', () {
      const sheet = TaskCreateSheet(
        quickMode: true,
        initialPriority: 'important',
        defaultDueToday: false,
      );

      expect(sheet.initialPriority, 'important');
      expect(sheet.defaultDueToday, isFalse);
    });
  });
}
