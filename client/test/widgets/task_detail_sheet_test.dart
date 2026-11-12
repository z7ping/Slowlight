import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/models/task.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/ui/theme_manager.dart';
import 'package:slowlight/theme/app_theme.dart';
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

  testWidgets('新建任务与详情共享相同字段树，并仅在输入标题后可创建',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final draft = Task(
      id: 0,
      listId: 1,
      title: '',
      priority: 'none',
      dueDate: DateTime(2026, 11, 5),
      isCompleted: false,
      createdAt: DateTime(2026, 11, 5),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskDetailSheet(
          task: draft,
          isCreating: true,
          lists: lists,
          onChanged: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('添加任务'), findsOneWidget);
    expect(find.text('任务详情'), findsNothing);
    expect(tester.widget<FxInput>(
      find.byKey(const ValueKey('task.detail.title')),
    ).plain, isTrue);
    expect(tester.widget<FxInput>(
      find.byKey(const ValueKey('task.detail.title')),
    ).showPlainFocusUnderline, isFalse);
    expect(tester.widget<FxInput>(
      find.byKey(const ValueKey('task.detail.title')),
    ).minLines, 4);
    for (final field in ['list', 'due', 'priority', 'tags']) {
      expect(find.byKey(ValueKey('task.detail.property.$field')),
          findsOneWidget);
    }
    expect(find.byKey(const ValueKey('task.detail.complete')), findsNothing);
    expect(find.byType(FxMenu<String>), findsNWidgets(4));
    final quickbar = find.byKey(const ValueKey('task.detail.quickbar'));
    expect(quickbar, findsOneWidget);
    final titleRect = tester.getRect(
      find.byKey(const ValueKey('task.detail.title')),
    );
    expect(titleRect.height, greaterThan(tester.getRect(quickbar).height),
        reason: 'Four visible title lines must dominate the compact quickbar');
    expect(tester.getSize(
      find.byKey(const ValueKey('task.detail.property.list')),
    ).width, lessThan(140), reason: 'List trigger must wrap its content');
    expect(tester.getSize(
      find.byKey(const ValueKey('task.detail.property.due')),
    ).width, lessThan(120), reason: 'Date trigger must not consume flex space');
    // The quadrant is colour-coded via its flag; never repeat its long
    // description in the compact one-row property bar.
    expect(find.descendant(
      of: find.byKey(const ValueKey('task.detail.property.priority')),
      matching: find.byIcon(LucideIcons.flag),
    ), findsOneWidget);
    expect(find.descendant(
      of: quickbar,
      matching: find.text('不重要 · 不紧急'),
    ), findsNothing);
    // Unset priority/tags stay icon-only in the compact quickbar.
    expect(
      find.descendant(of: quickbar, matching: find.text('未设置')),
      findsNothing,
    );
    final action = find.byKey(const ValueKey('task.detail.primaryAction'));
    // The primary icon is inside the entry border, right-aligned with props.
    expect(find.byKey(const ValueKey('task.detail.fixedFooter')), findsNothing);
    expect(
      find.ancestor(
        of: action,
        matching: find.byKey(const ValueKey('task.detail.workspace')),
      ),
      findsOneWidget,
    );
    expect(find.descendant(of: quickbar, matching: action), findsOneWidget);
    expect(tester.getRect(action).right,
        lessThanOrEqualTo(tester.getRect(quickbar).right));
    expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
    expect(find.text('添加任务'), findsOneWidget);
    expect(tester.widget<FxIconButton>(action).onPressed, isNull);
    expect(tester.widget<FxIconButton>(action).variant,
        FxIconButtonVariant.primary);
    expect(tester.widget<FxIconButton>(action).icon, LucideIcons.arrowUp);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('task.detail.title')),
        matching: find.byType(EditableText),
      ),
      '写下明天的计划',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FxIconButton>(action).onPressed, isNotNull);

    final cardCountBeforePopup = find.byType(FxCard).evaluate().length;
    await tester.tap(find.byKey(const ValueKey('task.detail.property.priority')));
    await tester.pumpAndSettle();
    // The Shad/Fx popover is the single floating surface: no nested FxCard.
    expect(find.byType(FxCard).evaluate().length, cardCountBeforePopup);
    final selected = find.byKey(
      const ValueKey('task.detail.option.不重要 · 不紧急'),
    );
    expect(selected, findsOneWidget);
    expect(tester.getSize(selected).height, inInclusiveRange(44, 64));
    expect(
      (tester.widget<Container>(selected).decoration as BoxDecoration).color,
      isNot(Colors.transparent),
    );
    expect(find.text('不重要 · 不紧急'), findsOneWidget);
    await tester.tap(find.text('重要 · 紧急'));
    await tester.pumpAndSettle();
    expect(find.text('添加任务'), findsOneWidget);
    expect(find.byKey(const ValueKey('task.detail.status')), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });


  testWidgets('Android 新建任务快捷属性操作保留标题焦点和键盘', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final draft = Task(
      id: 0,
      listId: lists.first.id,
      title: '',
      priority: 'none',
      isCompleted: false,
      createdAt: DateTime(2026, 11, 12),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskDetailSheet(
        task: draft,
        isCreating: true,
        lists: lists,
        onChanged: () {},
      )),
    ));
    await tester.pumpAndSettle();

    final title = find.descendant(
      of: find.byKey(const ValueKey('task.detail.title')),
      matching: find.byType(EditableText),
    );
    await tester.showKeyboard(title);
    await tester.enterText(title, '今晚整理记录');
    await tester.pumpAndSettle();

    void expectKeyboardAndDraft() {
      expect(tester.widget<EditableText>(title).focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.widget<EditableText>(title).controller.text, '今晚整理记录');
    }

    expectKeyboardAndDraft();
    // Checking the open state catches an IME dismissal before selection.
    for (final field in ['list', 'due', 'priority', 'tags']) {
      await tester.tap(find.byKey(ValueKey('task.detail.property.$field')));
      await tester.pumpAndSettle();
      expectKeyboardAndDraft();
      if (field == 'tags') {
        await tester.tap(find.text('完成').last);
      } else {
        final label = switch (field) {
          'list' => '${lists.first.icon} ${lists.first.name}',
          'due' => '明天',
          'priority' => '重要 · 紧急',
          _ => throw StateError('unexpected field'),
        };
        await tester.tap(find.byKey(ValueKey('task.detail.option.$label')));
      }
      await tester.pumpAndSettle();
      expectKeyboardAndDraft();
    }
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  for (final size in [const Size(320, 640), const Size(390, 850)]) {
    testWidgets('Android ${size.width.toInt()}dp 键盘展开后快捷浮窗位于触发按钮上方',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: size.height * .40);
      addTearDown(tester.view.reset);

      final draft = Task(
        id: 0,
        listId: lists.first.id,
        title: '',
        priority: 'none',
        isCompleted: false,
        createdAt: DateTime(2026, 11, 12),
      );
      await tester.pumpWidget(buildFxTestHost(
        home: Scaffold(body: TaskDetailSheet(
          task: draft, isCreating: true, lists: lists, onChanged: () {},
        )),
      ));
      await tester.pumpAndSettle();
      final title = find.descendant(
        of: find.byKey(const ValueKey('task.detail.title')),
        matching: find.byType(EditableText),
      );
      await tester.showKeyboard(title);
      await tester.enterText(title, '继续记录');
      await tester.pumpAndSettle();

      final trigger = find.byKey(const ValueKey('task.detail.property.priority'));
      final menu = find.ancestor(of: trigger,
          matching: find.byType(FxMenu<String>)).first;
      expect(tester.widget<FxMenu<String>>(menu).preferAbove, isTrue);
      final shadPopover = find.descendant(of: menu,
          matching: find.byType(ShadPopover));
      expect(tester.widget<ShadPopover>(shadPopover).anchor, isA<ShadAnchorAuto>());

      await tester.tap(trigger);
      await tester.pumpAndSettle();
      final firstOption = find.byKey(
          const ValueKey('task.detail.option.不重要 · 不紧急'));
      expect(firstOption, findsOneWidget);
      final triggerTop = tester.getTopLeft(trigger).dy;
      final optionRect = tester.getRect(firstOption);
      expect(optionRect.bottom, lessThanOrEqualTo(triggerTop),
          reason: 'The popover must be above its trigger, not under the IME');
      expect(optionRect.top, greaterThanOrEqualTo(-1),
          reason: 'A short viewport must constrain the menu to visible headroom');
      expect(optionRect.left, greaterThanOrEqualTo(-1),
          reason: 'A menu at the leftmost property must not be cut off');
      expect(optionRect.right, lessThanOrEqualTo(size.width + 1),
          reason: 'A menu at the rightmost property must not run offscreen');
      expect(tester.widget<EditableText>(title).focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.widget<EditableText>(title).controller.text, '继续记录');
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }

  for (final width in [320.0, 390.0]) {
    testWidgets('Android ${width.toInt()}dp 清单与标签菜单不能横向越界',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 340);
      addTearDown(tester.view.reset);
      final draft = Task(
        id: 0, listId: lists.first.id, title: '',
        priority: 'none', isCompleted: false,
        createdAt: DateTime(2026, 11, 12),
      );
      await tester.pumpWidget(buildFxTestHost(
        home: Scaffold(body: TaskDetailSheet(
          task: draft, isCreating: true,
          lists: lists, onChanged: () {},
        )),
      ));
      await tester.pumpAndSettle();
      final title = find.descendant(
        of: find.byKey(const ValueKey('task.detail.title')),
        matching: find.byType(EditableText),
      );
      await tester.showKeyboard(title);
      await tester.enterText(title, '记录一件事');
      await tester.pumpAndSettle();

      final listTrigger = find.byKey(const ValueKey('task.detail.property.list'));
      await tester.tap(listTrigger);
      await tester.pumpAndSettle();
      final listOption = find.byKey(
          ValueKey('task.detail.option.${lists.first.icon} ${lists.first.name}'));
      final listRect = tester.getRect(listOption);
      expect(listRect.left, greaterThanOrEqualTo(0));
      expect(listRect.right, lessThanOrEqualTo(width));
      await tester.tap(listOption);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('task.detail.property.tags')));
      await tester.pumpAndSettle();
      final tagRect = tester.getRect(find.byType(TagPicker).last);
      expect(tagRect.left, greaterThanOrEqualTo(0));
      expect(tagRect.right, lessThanOrEqualTo(width));
      expect(tester.widget<EditableText>(title).focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }

  testWidgets('Android 新建任务操作贴在输入框右下角，无独立底栏',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 340);
    addTearDown(tester.view.reset);
    final draft = Task(
      id: 0, listId: lists.first.id, title: '',
      priority: 'none', isCompleted: false,
      createdAt: DateTime(2026, 11, 12),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskDetailSheet(
        task: draft, isCreating: true, lists: lists, onChanged: () {},
      )),
    ));
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('task.detail.primaryAction'));
    final quickbar = find.byKey(const ValueKey('task.detail.quickbar'));
    final workspace = find.byKey(const ValueKey('task.detail.workspace'));
    expect(find.byKey(const ValueKey('task.detail.fixedFooter')), findsNothing);
    expect(find.descendant(of: workspace, matching: action), findsOneWidget);
    expect(find.descendant(of: quickbar, matching: action), findsOneWidget);
    expect(tester.getRect(action).right,
        lessThanOrEqualTo(tester.getRect(workspace).right));
    expect(tester.getRect(action).bottom,
        lessThanOrEqualTo(tester.getRect(workspace).bottom));
    expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 新建任务标题仅在可保存性变化时刷新提交态', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final draft = Task(
      id: 0,
      listId: lists.first.id,
      title: '',
      priority: 'none',
      isCompleted: false,
      createdAt: DateTime(2026, 11, 12),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskDetailSheet(
        task: draft,
        isCreating: true,
        lists: lists,
        onChanged: () {},
      )),
    ));
    await tester.pumpAndSettle();

    final title = find.descendant(
      of: find.byKey(const ValueKey('task.detail.title')),
      matching: find.byType(EditableText),
    );
    final save = find.byKey(const ValueKey('task.detail.primaryAction'));
    expect(tester.widget<FxIconButton>(save).onPressed, isNull);
    await tester.enterText(title, '   ');
    await tester.pumpAndSettle();
    expect(tester.widget<FxIconButton>(save).onPressed, isNull);
    await tester.enterText(title, '  一项任务');
    await tester.pumpAndSettle();
    expect(tester.widget<FxIconButton>(save).onPressed, isNotNull);
    await tester.enterText(title, '    ');
    await tester.pumpAndSettle();
    expect(tester.widget<FxIconButton>(save).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Android 属性栏 ${width}dp / ${scale}x 始终单行',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(buildFxTestHost(
          home: Scaffold(
            body: TaskDetailSheet(
              task: task,
              lists: [
                TodoList(
                  id: 1,
                  name: '一个很长很长的工作项目清单',
                  color: '#1890ff',
                  createdAt: DateTime(2026, 10, 16),
                ),
              ],
              onChanged: () {},
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
        ));
        await tester.pumpAndSettle();
        final quickbar = find.byKey(
          const ValueKey('task.detail.quickbar'),
        );
        expect(tester.widget<Row>(quickbar).children.length, 9);
        final triggerRects = [
          for (final field in ['list', 'due', 'priority', 'tags'])
            tester.getRect(find.byKey(ValueKey('task.detail.property.$field'))),
        ];
        expect(
          triggerRects.map((rect) => rect.top).reduce((a, b) =>
              a > b ? a : b) -
              triggerRects.map((rect) => rect.top).reduce((a, b) =>
                  a < b ? a : b),
          lessThan(1),
        );
        for (final rect in triggerRects) {
          expect(rect.height, greaterThanOrEqualTo(44));
        }
        expect(
          tester.getRect(quickbar).right,
          lessThanOrEqualTo(width),
        );
        expect(find.byKey(const ValueKey('task.detail.status')), findsNothing);
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }
  }

  testWidgets('更多设置保持紧凑，未安排日期时提醒先提示约束',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskDetailSheet(task: task, lists: lists, onChanged: () {}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task.detail.status')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('task.detail.moreSettings')));
    await tester.pumpAndSettle();
    expect(tester.widget<FxInput>(
      find.byKey(const ValueKey('task.detail.description')),
    ).minLines, 1);
    await tester.tap(find.byKey(const ValueKey('task.detail.property.reminder')));
    await tester.pumpAndSettle();
    expect(
      find.text('提前提醒需先安排日期；也可指定独立提醒时间'),
      findsOneWidget,
    );
    final relativeReminder = find.text('提前 5 分钟');
    expect(relativeReminder, findsOneWidget);
    final row = find.ancestor(
      of: relativeReminder,
      matching: find.byType(FxInkWell),
    ).first;
    expect(tester.widget<FxInkWell>(row).onTap, isNull);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 任务清单日期优先级菜单都左对齐且选中勾选靠右',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 850);
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

    final cases = [
      ('list', '${lists.first.icon} ${lists.first.name}'),
      ('due', '不设置'),
      ('priority', '不重要 · 不紧急'),
    ];
    for (final (field, label) in cases) {
      await tester.tap(find.byKey(ValueKey('task.detail.property.$field')));
      await tester.pumpAndSettle();
      final item = find.byKey(ValueKey('task.detail.option.$label'));
      expect(item, findsOneWidget);
      final trigger = find.byKey(ValueKey('task.detail.property.$field'));
      final menu = tester.widget<FxMenu<String>>(
        find.ancestor(
          of: trigger,
          matching: find.byType(FxMenu<String>),
        ).first,
      );
      final expectedWidth = switch (field) {
        'due' => 196.0,
        'priority' => 220.0,
        'list' => 236.0,
        _ => throw StateError('unexpected field'),
      };
      expect(menu.constraints!.minWidth, expectedWidth);
      expect(menu.constraints!.maxWidth, expectedWidth);
      expect(tester.getRect(item).width, lessThanOrEqualTo(expectedWidth));
      final selectedBackground =
          (tester.widget<Container>(item).decoration as BoxDecoration).color;
      final selectedColor = field == 'priority'
          ? Theme.of(tester.element(item)).colorScheme.onSurfaceVariant
          : activePalette.accent;
      expect(selectedBackground, selectedColor.withValues(alpha: .09));
      final text = find.descendant(of: item, matching: find.text(label));
      expect(text, findsOneWidget);
      expect(
        DefaultTextStyle.of(tester.element(text)).textAlign,
        TextAlign.start,
        reason: '$field must not inherit centered ShadPopover text',
      );
      final itemRect = tester.getRect(item);
      final labelRect = tester.getRect(text);
      expect(labelRect.left,
          closeTo(itemRect.left + (field == 'priority' ? 34 : 12), 2),
          reason: '$field option text must clear any semantic flag icon');
      if (field == 'priority') {
        final quadrantFlag = find.descendant(
          of: item,
          matching: find.byIcon(LucideIcons.flag),
        );
        expect(quadrantFlag, findsOneWidget);
        expect(tester.widget<Icon>(quadrantFlag).color,
            Theme.of(tester.element(item)).colorScheme.onSurfaceVariant);
      }
      final checks = find.descendant(
        of: item,
        matching: find.byIcon(LucideIcons.check),
      );
      expect(checks, findsOneWidget);
      // Expanded Text fills its row even when glyphs are start-aligned.
      // Assert the check stays at the trailing inset, not beside the text.
      expect(tester.getRect(checks).right, closeTo(itemRect.right - 12, 2));
      expect(
        tester.getTopLeft(checks).dx,
        greaterThanOrEqualTo(labelRect.right - 1),
      );
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    // A changed priority is immediately visible on its closed trigger:
    // meaningful priority colour, not just a generic selected tick.
    await tester.tap(find.byKey(const ValueKey('task.detail.property.priority')));
    await tester.pumpAndSettle();
    for (final (label, expectedColor) in [
      ('重要 · 紧急', AppTheme.priorityHigh),
      ('重要 · 不紧急', AppTheme.priorityMedium),
      ('不重要 · 紧急', AppTheme.priorityLow),
    ]) {
      final option = find.byKey(ValueKey('task.detail.option.$label'));
      final flag = find.descendant(of: option,
          matching: find.byIcon(LucideIcons.flag));
      expect(flag, findsOneWidget);
      expect(tester.widget<Icon>(flag).color, expectedColor);
    }
    await tester.tap(
      find.byKey(const ValueKey('task.detail.option.重要 · 紧急')),
    );
    await tester.pumpAndSettle();
    final flag = find.descendant(
      of: find.byKey(const ValueKey('task.detail.property.priority')),
      matching: find.byIcon(LucideIcons.flag),
    );
    expect(tester.widget<Icon>(flag).color, AppTheme.priorityHigh);
    expect(find.descendant(
      of: find.byKey(const ValueKey('task.detail.quickbar')),
      matching: find.text('重要 · 紧急'),
    ), findsNothing);
    await tester.tap(find.byKey(const ValueKey('task.detail.property.priority')));
    await tester.pumpAndSettle();
    final selectedPriority = find.byKey(
      const ValueKey('task.detail.option.重要 · 紧急'),
    );
    expect(
      (tester.widget<Container>(selectedPriority).decoration as BoxDecoration).color,
      AppTheme.priorityHigh.withValues(alpha: .09),
    );
    expect(
      tester.widget<Icon>(find.descendant(
        of: selectedPriority,
        matching: find.byIcon(LucideIcons.check),
      )).color,
      AppTheme.priorityHigh,
    );
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });


  testWidgets('320dp 及 200% 字号下清单浮窗不超出可用宽度', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final longLists = [
      TodoList(
        id: 1,
        name: '一个名字很长但不应该被选项弹窗直接裁掉的清单',
        color: '#1890ff',
        createdAt: DateTime(2026, 11, 11),
      ),
    ];
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskDetailSheet(
          task: task,
          lists: longLists,
          onChanged: () {},
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
    ));
    await tester.pumpAndSettle();

    final trigger = find.byKey(const ValueKey('task.detail.property.list'));
    final menu = tester.widget<FxMenu<String>>(
      find.ancestor(of: trigger, matching: find.byType(FxMenu<String>)).first,
    );
    expect(menu.constraints!.minWidth, lessThanOrEqualTo(288));
    expect(menu.constraints!.minWidth, menu.constraints!.maxWidth);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    // The label is allowed to wrap instead of increasing menu width.
    // The actual icon prefix is data-driven; test the visible selection.
    expect(find.textContaining('一个名字很长但不应该被选项弹窗直接裁掉的清单'), findsWidgets);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X01 外部入口预填清单和标题时取消必须保护原始草稿',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final options = [
      ...lists,
      TodoList(id: 2, name: '项目清单',
          color: '#1890ff', createdAt: DateTime(2026, 10, 16)),
    ];
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(builder: (context) => FxButton(
        label: '带预填打开',
        onPressed: () => TaskDetailSheet.showCreate(
          context,
          lists: options,
          selectedListId: 2,
          initialTitle: '来自外部入口的标题',
          defaultDueToday: false,
          onChanged: () {},
        ),
      ))),
    ));
    await tester.tap(find.text('带预填打开'));
    await tester.pumpAndSettle();
    final editor = find.byType(TaskDetailSheet);
    expect(editor, findsOneWidget);
    expect(tester.widget<TaskDetailSheet>(editor).task.listId, 2);
    expect(find.text('项目清单'), findsOneWidget);
    expect(find.text('来自外部入口的标题'), findsOneWidget);

    await tester.tap(fxTooltipFinder('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('放弃新建任务？'), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(find.text('来自外部入口的标题'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X01 显式清单失效不得静默回退到其他清单创建', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(builder: (context) => FxButton(
        label: '打开已失效清单',
        onPressed: () => TaskDetailSheet.showCreate(
          context,
          lists: lists,
          selectedListId: 999,
          onChanged: () {},
        ),
      ))),
    ));
    await tester.tap(find.text('打开已失效清单'));
    await tester.pump();
    expect(find.byType(TaskDetailSheet), findsNothing);
    expect(find.text('目标清单暂不可用，请刷新后重新创建任务'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X01 Android 输入法收起前后内容与固定保存区仍在同一 Sheet',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(builder: (context) => FxButton(
        label: '打开带键盘任务',
        onPressed: () => TaskDetailSheet.showCreate(
          context, lists: lists, onChanged: () {},
        ),
      ))),
    ));
    await tester.tap(find.text('打开带键盘任务'));
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: find.byKey(const ValueKey('task.detail.title')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(input, '输入法展开期间的任务');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(() => tester.view.viewInsets = const FakeViewPadding());
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('task.detail.primaryAction'));
    expect(save, findsOneWidget);
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(850));
    expect(find.text('输入法展开期间的任务'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsOneWidget);
    expect(tester.widget<FxIconButton>(save).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 长任务表单滚动后可重新找到输入框内保存入口',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 560);
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
    await tester.tap(find.byKey(const ValueKey('task.detail.moreSettings')));
    await tester.pumpAndSettle();

    final save = find.byKey(const ValueKey('task.detail.primaryAction'));
    await tester.drag(find.byType(SingleChildScrollView).first,
        const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expect(
      find.ancestor(of: save,
          matching: find.byKey(const ValueKey('task.detail.workspace'))),
      findsOneWidget,
    );
    expect(tester.getSize(save).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 任务新建携带来自日历的日期和四象限优先级',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(
          builder: (context) => FxButton(
            label: '打开创建',
            onPressed: () => TaskDetailSheet.showCreate(
              context,
              lists: lists,
              onChanged: () {},
              initialDueDate: DateTime(2026, 11, 21),
              initialPriority: 'urgent_important',
              defaultDueToday: false,
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开创建'));
    await tester.pumpAndSettle();

    final detail = find.byType(TaskDetailSheet);
    expect(detail, findsOneWidget);
    final draft = tester.widget<TaskDetailSheet>(detail).task;
    expect(draft.dueDate, DateTime(2026, 11, 21));
    expect(draft.priority, 'urgent_important');
    expect(tester.widget<TaskDetailSheet>(detail).isCreating, isTrue);
    expect(find.text('添加任务'), findsOneWidget);
    expect(find.text('重要 · 紧急'), findsOneWidget);
    expect(find.text('2026-11-21'), findsOneWidget);
    final title = find.descendant(
      of: find.byKey(const ValueKey('task.detail.title')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(title).focusNode.hasFocus, isTrue);
    // The main form grows with content but never occupies the whole viewport.
    expect(tester.getSize(detail).height, lessThan(820));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 修改任务标题后撤回原值不会留下虚假的未保存状态',
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

    final title = find.descendant(
      of: find.byKey(const ValueKey('task.detail.title')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(title, '临时修改');
    await tester.pumpAndSettle();
    expect(find.text('有未保存的修改'), findsOneWidget);

    await tester.enterText(title, task.title);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task.detail.status')), findsNothing);
    expect(
      tester.widget<FxButton>(
        find.byKey(const ValueKey('task.detail.primaryAction')),
      ).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 重新选中相同优先级不误报未保存',
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
    await tester.tap(find.byKey(const ValueKey('task.detail.property.priority')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不重要 · 不紧急'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task.detail.status')), findsNothing);
    expect(find.text('有未保存的修改'), findsNothing);
    expect(
      tester.widget<FxButton>(
        find.byKey(const ValueKey('task.detail.primaryAction')),
      ).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

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
    expect(tester.widget<FxInput>(
      find.byKey(const ValueKey('task.detail.title')),
    ).plain, isTrue);
    expect(find.byKey(const ValueKey('task.detail.property.list')), findsOneWidget);
    expect(find.byKey(const ValueKey('task.detail.property.due')), findsOneWidget);
    expect(find.byKey(const ValueKey('task.detail.property.priority')), findsOneWidget);
    expect(find.byKey(const ValueKey('task.detail.property.tags')), findsOneWidget);
    expect(find.byKey(const ValueKey('task.detail.property.repeat')), findsNothing);
    expect(find.text('时间安排'), findsNothing);
    expect(find.byType(TagPicker), findsNothing);
    expect(find.text('历史分类（兼容）'), findsNothing);
    expect(tester.widget<FxIconButton>(
      find.byKey(const ValueKey('task.detail.primaryAction')),
    ).tooltip, '保存修改');
    expect(find.byKey(const ValueKey('task.detail.status')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('task.detail.property.priority')));
    await tester.pumpAndSettle();
    // The editor remains on the same sheet; choice options float by the row.
    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('设置优先级'), findsNothing);
    expect(find.text('不重要 · 不紧急'), findsOneWidget);
    expect(find.text('重要 · 紧急'), findsOneWidget);
    await tester.tap(find.text('重要 · 紧急'));
    await tester.pumpAndSettle();
    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('有未保存的修改'), findsOneWidget);
    final save = tester.widget<FxIconButton>(find.byKey(const ValueKey('task.detail.primaryAction')));
    expect(save.onPressed, isNotNull);

    await tester.ensureVisible(find.byKey(const ValueKey('task.detail.property.tags')));
    await tester.tap(find.byKey(const ValueKey('task.detail.property.tags')));
    await tester.pumpAndSettle();
    expect(find.byType(TagPicker), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('task.detail.moreSettings')));
    await tester.pumpAndSettle();
    expect(find.byType(FxResponsiveFormGrid), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('task.detail.property.repeat')));
    await tester.tap(find.byKey(const ValueKey('task.detail.property.repeat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每周'));
    await tester.pumpAndSettle();
    expect(find.text('选择星期'), findsOneWidget);
    expect(find.byType(FxChoiceChip), findsNWidgets(7));
    expect(find.text('有未保存的修改'), findsOneWidget);
    expect(find.text('修改后返回详情'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 相对提醒复用任务日期时间，10 分钟预设可选且不立即写入',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final scheduled = Task(
      id: 71,
      listId: 1,
      title: '定时准备',
      priority: 'none',
      isCompleted: false,
      dueDate: DateTime(2026, 11, 20),
      dueTime: '12:00',
      createdAt: DateTime(2026, 11, 5),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TaskDetailSheet(
          task: scheduled,
          lists: lists,
          onChanged: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task.detail.moreSettings')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('task.detail.property.reminder')),
    );
    await tester.tap(find.byKey(const ValueKey('task.detail.property.reminder')));
    await tester.pumpAndSettle();

    expect(find.text('准时'), findsOneWidget);
    expect(find.text('提前 10 分钟'), findsOneWidget);
    expect(find.text('提前 1 小时'), findsOneWidget);
    expect(find.text('自定义日期与时间…'), findsOneWidget);

    await tester.tap(find.text('提前 10 分钟'));
    await tester.pumpAndSettle();
    expect(find.text('提前 10 分钟'), findsOneWidget);
    expect(find.text('有未保存的修改'), findsOneWidget);
    expect(find.byType(TaskDetailSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X02 详情移除到期日期后相对提醒回填为不提醒',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scheduled = Task(
      id: 82,
      listId: 1,
      title: '需要提前准备的任务',
      priority: 'none',
      isCompleted: false,
      dueDate: DateTime(2026, 11, 20),
      dueTime: '12:00',
      reminderAt: DateTime(2026, 11, 20, 11, 50),
      reminderAdvanceMinutes: 10,
      createdAt: DateTime(2026, 11, 5),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskDetailSheet(
        task: scheduled, lists: lists, onChanged: () {},
      )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task.detail.moreSettings')));
    await tester.pumpAndSettle();
    expect(find.text('提前 10 分钟'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('task.detail.property.due')));
    await tester.tap(find.byKey(const ValueKey('task.detail.property.due')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不设置'));
    await tester.pumpAndSettle();
    expect(find.text('不提醒'), findsOneWidget);
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

  testWidgets('Android 暗色 320dp 高字号弹层保持可滚动和固定保存入口',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      theme: ThemeManager.darkTheme,
      shadTheme: ThemeManager.shadDark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.3),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: TaskDetailSheet(task: task, lists: lists, onChanged: () {}),
      ),
    ));
    await tester.pumpAndSettle();

    final footer = find.byKey(const ValueKey('task.detail.primaryAction'));
    expect(footer, findsOneWidget);
    final rect = tester.getRect(footer);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
    expect(rect.bottom, lessThanOrEqualTo(640));
    final more = find.byKey(const ValueKey('task.detail.moreSettings'));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task.detail.property.repeat')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X04 Windows 独立任务详情防止遮罩和系统返回丢失修改',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(
          builder: (context) => FxButton(
            label: '打开独立任务详情',
            onPressed: () => TaskDetailSheet.show(
              context, task: task, lists: lists, onChanged: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开独立任务详情'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '修改后的标题');
    await tester.pump();

    await tester.tapAt(const Offset(4, 80));
    await tester.pump();
    expect(find.byType(TaskDetailSheet), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText).first)
          .controller.text,
      '修改后的标题',
    );

    await tester.tap(fxTooltipFinder('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailSheet), findsNothing);
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
  testWidgets('P04 Windows 日期/时间清除更新相对提醒，不残留旧值', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scheduled = Task(
      id: 88, listId: 1, title: '带提醒的任务',
      priority: 'none', isCompleted: false,
      dueDate: DateTime(2026, 11, 9), dueTime: '16:20',
      reminderAt: DateTime(2026, 11, 9, 16, 10),
      reminderAdvanceMinutes: 10,
      createdAt: DateTime(2026, 11, 5),
    );
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: SizedBox(
        width: 440, height: 850,
        child: TaskDetailSheet(
          task: scheduled, lists: lists, sidePanel: true, onChanged: () {},
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('2026-11-09 16:10'), findsOneWidget);
    final clearTime = find.byWidgetPredicate((widget) =>
        widget is FxIconButton && widget.tooltip == '清除时间');
    expect(clearTime, findsOneWidget);
    tester.widget<FxIconButton>(clearTime).onPressed?.call();
    await tester.pumpAndSettle();
    expect(find.text('2026-11-09 08:50'), findsOneWidget);
    final clearDate = find.byWidgetPredicate((widget) =>
        widget is FxIconButton && widget.tooltip == '清除到期日期');
    expect(clearDate, findsOneWidget);
    tester.widget<FxIconButton>(clearDate).onPressed?.call();
    await tester.pumpAndSettle();
    expect(find.text('2026-11-09 08:50'), findsNothing);
    expect(find.text('不提醒'), findsOneWidget);
    expect(find.text('清除提醒'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
