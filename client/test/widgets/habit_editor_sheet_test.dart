import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/habit_editor_dialog.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('Android habit editor opens a single sheet and cancels safely',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(
          builder: (context) => FxButton(
            label: '打开习惯编辑',
            onPressed: () async {
              await HabitEditorDialog.show(context);
            },
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开习惯编辑'));
    await tester.pumpAndSettle();

    expect(fxSheetSurfaceFinder(), findsOneWidget);
    expect(fxDialogSurfaceFinder(), findsNothing);
    expect(find.text('添加习惯'), findsOneWidget);
    expect(find.text('创建习惯'), findsOneWidget);
    expect(find.byKey(const ValueKey('habit-editor-mobile-footer')),
        findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitEditorDialog), findsNothing);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows habit editor continues to use a dialog',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(
          builder: (context) => FxButton(
            label: '打开习惯编辑',
            onPressed: () async {
              await HabitEditorDialog.show(context);
            },
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开习惯编辑'));
    await tester.pumpAndSettle();

    expect(fxDialogSurfaceFinder(), findsWidgets);
    expect(fxSheetSurfaceFinder(), findsNothing);
    expect(find.text('创建习惯'), findsOneWidget);
    expect(find.byKey(const ValueKey('habit-editor-mobile-footer')),
        findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await disposeFxTestHost(tester);
  });
}
