import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/services/data_mode_manager.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/task_detail_sheet.dart';

import '../helpers/isolated_test_db.dart';
import '../support/fx_test_host.dart';

void main() {
  setUpAll(() async {
    await useIsolatedTestDb('task_detail_unknown_write');
    SharedPreferences.setMockInitialValues({'data_mode': 'local'});
    FlutterSecureStorage.setMockInitialValues({});
    await DataModeManager().setLocal();
  });

  testWidgets('X01 保存结果未知后禁止重复写入，允许核对后关闭',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final task = Task(
      id: 909012, // Intentionally absent from the isolated local database.
      listId: 1,
      title: '未确认写入的任务',
      isCompleted: false,
      priority: 'none',
      createdAt: DateTime(2026, 11, 8),
    );
    final lists = [
      TodoList(
        id: 1, name: '工作',
        color: '#1890ff', createdAt: DateTime(2026, 11, 8),
      ),
    ];
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '打开编辑',
          onPressed: () => TaskDetailSheet.show(
            context, task: task, lists: lists, onChanged: () {},
          ),
        ),
      )),
    ));

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
    final title = find.descendant(
      of: find.byKey(const ValueKey('task.detail.title')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(title, '已修改但无可确认的保存结果');
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('task.detail.primaryAction'));
    expect(tester.widget<FxButton>(save).onPressed, isNotNull);
    await tester.tap(save);
    await tester.pumpAndSettle();

    // A local update for an absent task cannot be confirmed successful.
    expect(find.text('任务变更结果未确认，请先核对'), findsOneWidget);
    expect(find.text('结果待核对'), findsOneWidget);
    expect(tester.widget<FxButton>(save).onPressed, isNull);

    await tester.tap(fxTooltipFinder('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('任务变更结果未确认'), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(find.text('已修改但无可确认的保存结果'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
