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
    final footer = find.byKey(const ValueKey('habit-editor-mobile-footer'));
    expect(footer, findsOneWidget);
    final cancel = find.descendant(
      of: footer, matching: find.widgetWithText(FxButton, '取消'),
    );
    final submit = find.descendant(
      of: footer, matching: find.widgetWithText(FxButton, '创建习惯'),
    );
    expect(cancel, findsOneWidget);
    expect(submit, findsOneWidget);
    // V3 high fidelity keeps two full-width touch targets in a 5:7 ratio.
    final ratio = tester.getSize(submit).width / tester.getSize(cancel).width;
    expect(ratio, closeTo(1.4, 0.02));
    expect(tester.getSize(cancel).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(submit).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitEditorDialog), findsNothing);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 200% 字号下习惯操作区改双行且主操作避让键盘',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '打开习惯编辑大字',
          onPressed: () => HabitEditorDialog.show(context),
        ),
      )),
    ));
    await tester.tap(find.text('打开习惯编辑大字'));
    await tester.pumpAndSettle();
    final footer = find.byKey(const ValueKey('habit-editor-mobile-footer'));
    final cancel = find.descendant(
      of: footer, matching: find.widgetWithText(FxButton, '取消'),
    );
    final save = find.byKey(const ValueKey('habit-editor-primary-action'));
    expect(footer, findsOneWidget);
    expect(cancel, findsOneWidget);
    expect(save, findsOneWidget);
    expect(tester.getSize(cancel).width, closeTo(tester.getSize(save).width, 1));
    expect(tester.getTopLeft(save).dy,
        greaterThan(tester.getBottomLeft(cancel).dy));
    expect(tester.getSize(cancel).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(save).height, greaterThanOrEqualTo(44));

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(800 - 280 + 1));
    expect(tester.takeException(), isNull);
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
