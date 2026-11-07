import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/habit.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/habit_editor_dialog.dart';
import 'package:slowlight/widgets/habit_checkin_dialog.dart';
import 'package:slowlight/widgets/reflection_composer.dart';
import 'package:slowlight/widgets/task_detail_sheet.dart';

import '../support/fx_test_host.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('普通移动 Sheet 的显式引导线和 16dp 顶角与原型一致',
      (tester) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '打开选项',
          onPressed: () => FxSheet.show<void>(
            context: context,
            showDragHandle: true,
            builder: (_) => const SizedBox(
              height: 180,
              child: Center(child: Text('可安全关闭的选项')),
            ),
          ),
        ),
      )),
    ));
    await tester.tap(find.text('打开选项'));
    await tester.pumpAndSettle();
    final grip = find.byKey(const ValueKey('fx.sheet.visualHandle'));
    expect(grip, findsOneWidget);
    expect(tester.getSize(grip).height, 44);
    final sheet = tester.widget<ShadSheet>(fxSheetSurfaceFinder());
    expect(
      sheet.radius,
      const BorderRadius.vertical(top: Radius.circular(SlowlightRadius.xl)),
    );
    expect(sheet.draggable, isTrue);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('明确隐藏引导线的受保护表单仍禁止整面拖拽', (tester) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '打开无引导线表单',
          onPressed: () => FxSheet.show<void>(
            context: context,
            showDragHandle: false,
            draggable: true,
            isDismissible: false,
            onDismissRequested: () async {},
            builder: (_) => const SizedBox(
              height: 180,
              child: Center(child: Text('含未保存内容')),
            ),
          ),
        ),
      )),
    ));
    await tester.tap(find.text('打开无引导线表单'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fx.sheet.dragHandle')), findsNothing);
    expect(find.byKey(const ValueKey('fx.sheet.visualHandle')), findsNothing);
    final sheet = tester.widget<ShadSheet>(fxSheetSurfaceFinder());
    expect(sheet.draggable, isFalse);
    expect(
      sheet.radius,
      const BorderRadius.vertical(top: Radius.circular(SlowlightRadius.xl)),
    );
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });


  testWidgets('统一引导线：轻拖回弹，长拖请求退出；内容滑动不能关闭',
      (tester) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var closeRequests = 0;
    BuildContext? activeContext;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '打开表单',
          onPressed: () => FxSheet.show<void>(
            context: context,
            isDismissible: false,
            draggable: false,
            showCloseButton: false,
            onDismissRequested: () async {
              closeRequests++;
              if (activeContext?.mounted ?? false) {
                Navigator.of(activeContext!).pop();
              }
            },
            builder: (sheetContext) {
              activeContext = sheetContext;
              return SizedBox(
                height: 260,
                child: SingleChildScrollView(
                  child: Column(children: [
                    for (var i = 0; i < 12; i++)
                      SizedBox(height: 44, child: Text('内容 $i')),
                  ]),
                ),
              );
            },
          ),
        ),
      )),
    ));
    await tester.tap(find.text('打开表单'));
    await tester.pumpAndSettle();
    final handle = find.byKey(const ValueKey('fx.sheet.dragHandle'));
    expect(handle, findsOneWidget);
    await tester.drag(find.text('内容 0'), const Offset(0, -90));
    await tester.pumpAndSettle();
    expect(closeRequests, 0);

    await tester.drag(handle, const Offset(0, 26));
    await tester.pumpAndSettle();
    expect(closeRequests, 0);
    expect(handle, findsOneWidget);

    await tester.drag(handle, const Offset(0, 175));
    await tester.pumpAndSettle();
    expect(closeRequests, 1);
    expect(handle, findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('观察 Sheet 下拉后走现有未保存草稿确认', (tester) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '记录观察',
          onPressed: () => ReflectionComposer.show(
            context,
            entryType: 'observation',
          ),
        ),
      )),
    ));
    await tester.tap(find.text('记录观察'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '保留观察草稿');
    await tester.drag(
      find.byKey(const ValueKey('fx.sheet.dragHandle')),
      const Offset(0, 170),
    );
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的观察？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('保留观察草稿'), findsOneWidget);
    expect(find.text('保存观察'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('任务 Sheet 下拉复用已有草稿确认，不直接提交或丢稿', (tester) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final lists = [
      TodoList(id: 1, name: '收集箱', color: '#1890ff', createdAt: now),
    ];
    final task = Task(
      id: 0, listId: 1, title: '', priority: 'none',
      isCompleted: false, createdAt: now,
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '打开任务',
          onPressed: () => TaskDetailSheet.show(
            context,
            task: task,
            lists: lists,
            isCreating: true,
            onChanged: () {},
          ),
        ),
      )),
    ));
    await tester.tap(find.text('打开任务'));
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: find.byKey(const ValueKey('task.detail.title')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(input, '未保存的新任务');
    await tester.drag(
      find.byKey(const ValueKey('fx.sheet.dragHandle')),
      const Offset(0, 170),
    );
    await tester.pumpAndSettle();
    expect(find.text('放弃新建任务？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('未保存的新任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('习惯 Sheet 模板改变后，拖动关闭必须确认', (tester) async {
    tester.view.physicalSize = const Size(390, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '打开习惯',
          onPressed: () => HabitEditorDialog.show(context),
        ),
      )),
    ));
    await tester.tap(find.text('打开习惯'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '调整中的习惯');
    await tester.drag(
      find.byKey(const ValueKey('fx.sheet.dragHandle')),
      const Offset(0, 170),
    );
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的习惯？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('调整中的习惯'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('习惯打卡 Sheet 下拉保留未保存的备注', (tester) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final habit = Habit(
      id: 1,
      userId: 1,
      name: '每日阅读',
      icon: '📚',
      color: '#1890ff',
      frequency: 'daily',
      checkedToday: false,
      createdAt: DateTime.now(),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '记录习惯',
          onPressed: () => HabitCheckinDialog.show(context, habit: habit),
        ),
      )),
    ));
    await tester.tap(find.text('记录习惯'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '未保存的打卡说明');
    await tester.drag(
      find.byKey(const ValueKey('fx.sheet.dragHandle')),
      const Offset(0, 170),
    );
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的记录？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('未保存的打卡说明'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('短确认沿用紧凑对话框，不存在可拖动引导线', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '删除确认',
          onPressed: () => FxDialog.confirm(
            context: context,
            title: '确认删除？',
            content: '这项操作不可撤销。',
            destructive: true,
          ),
        ),
      )),
    ));
    await tester.tap(find.text('删除确认'));
    await tester.pumpAndSettle();
    expect(find.text('确认删除？'), findsOneWidget);
    expect(find.byKey(const ValueKey('fx.sheet.dragHandle')), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
