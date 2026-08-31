import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/todo_list.dart';
import 'package:slowlight/screens/add_task_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  final testLists = [
    TodoList(id: 1, name: '工作', color: '#ff0000', createdAt: DateTime(2026)),
  ];

  AddTaskScreen buildScreen({bool embedded = false}) => AddTaskScreen(
    lists: testLists,
    selectedListId: 1,
    embedded: embedded,
  );

  group('AddTaskScreen 稳定契约', () {
    testWidgets('空标题提交会被校验拦截', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: buildScreen()));
      await tester.pump();

      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(find.text('请输入任务标题'), findsOneWidget);
      expect(find.byType(AddTaskScreen), findsOneWidget);
      await disposeFxTestHost(tester);
    });

    testWidgets('窄屏表单不产生布局异常', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildFxTestHost(home: buildScreen()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('桌面嵌入表单只保留弹窗壳关闭入口且操作区靠右', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      await tester.pumpWidget(
        buildFxTestHost(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 560,
              child: buildScreen(embedded: true),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('新建任务'), findsOneWidget);
      expect(find.byTooltip('关闭'), findsNothing);
      expect(tester.getCenter(find.text('保存')).dx, greaterThan(450));
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('Windows 新建任务保持桌面高密度排版', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      await tester.pumpWidget(
        buildFxTestHost(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 560,
              child: buildScreen(embedded: true),
            ),
          ),
        ),
      );
      await tester.pump();

      final titleInput = tester.widget<EditableText>(find.byType(EditableText).first);
      expect(
        titleInput.style.fontSize,
        SlowlightTypography.desktopEmphasizedInputSize,
      );
      expect(
        tester.widget<Text>(find.text('清单')).style?.fontSize,
        SlowlightTypography.desktopFieldLabelSize,
      );
      expect(
        tester.widget<Text>(find.text('工作')).style?.fontSize,
        SlowlightTypography.desktopChipSize,
      );
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });

    testWidgets('Android 新建任务使用 Android 可读排版', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      await tester.pumpWidget(
        buildFxTestHost(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 740,
              child: buildScreen(),
            ),
          ),
        ),
      );
      await tester.pump();

      final titleInput = tester.widget<EditableText>(find.byType(EditableText).first);
      expect(titleInput.style.fontSize, SlowlightTypography.bodySize);
      expect(
        tester.widget<Text>(find.text('清单')).style?.fontSize,
        SlowlightTypography.fieldLabelSize,
      );
      expect(
        tester.widget<Text>(find.text('工作')).style?.fontSize,
        SlowlightTypography.chipSize,
      );
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  });
}
