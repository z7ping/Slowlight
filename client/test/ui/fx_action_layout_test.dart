import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  Widget actionBar({required double width, required double scale}) {
    return Center(
      child: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(scale),
        ),
        child: SizedBox(
          width: width,
          child: FxActionBar(
            leading: const Text('筛选条件'),
            actions: [
              FxButton(
                label: '新建任务',
                size: FxButtonSize.sm,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget dialogActions({required double width, required double scale}) {
    return Center(
      child: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(scale),
        ),
        child: SizedBox(
          width: width,
          child: FxDialogActions(
            stackBelow: 340,
            leading: FxButton(
              label: '删除',
              variant: FxButtonVariant.ghost,
              onPressed: () {},
            ),
            actions: [FxButton(label: '保存', onPressed: () {})],
          ),
        ),
      ),
    );
  }

  testWidgets('FxActionBar 宽布局固定左上下文与右侧动作', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: Scaffold(body: actionBar(width: 720, scale: 1)),
      ),
    );

    final leading = tester.getRect(find.text('筛选条件'));
    final action = tester.getRect(find.text('新建任务'));
    expect(action.center.dx, greaterThan(leading.center.dx));
    expect(action.center.dy, closeTo(leading.center.dy, 12));
    expect(action.right, greaterThan(600));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('FxActionBar 窄屏大字体时动作下移但继续右对齐', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: Scaffold(body: actionBar(width: 360, scale: 2)),
      ),
    );

    final leading = tester.getRect(find.text('筛选条件'));
    final action = tester.getRect(find.text('新建任务'));
    expect(action.top, greaterThanOrEqualTo(leading.bottom));
    expect(action.center.dx, greaterThan(240));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('FxDialogActions 允许破坏性动作左置且主动作保持最右', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 560,
              child: FxDialogActions(
                leading: FxButton(
                  label: '删除',
                  variant: FxButtonVariant.ghost,
                  onPressed: () {},
                ),
                actions: [FxButton(label: '保存', onPressed: () {})],
              ),
            ),
          ),
        ),
      ),
    );

    final destructive = tester.getRect(find.text('删除'));
    final primary = tester.getRect(find.text('保存'));
    expect(primary.center.dx, greaterThan(destructive.center.dx));
    expect(primary.right, greaterThan(480));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('FxDialogActions 可按实际宽度保持紧凑编辑 Footer', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: Scaffold(body: dialogActions(width: 380, scale: 1)),
      ),
    );

    final destructive = tester.getRect(find.text('删除'));
    final primary = tester.getRect(find.text('保存'));
    expect(primary.center.dy, closeTo(destructive.center.dy, 12));
    expect(primary.center.dx, greaterThan(destructive.center.dx));
    expect(primary.right, greaterThan(330));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('FxDialogActions 超大字体时仍会自然分行', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: Scaffold(body: dialogActions(width: 380, scale: 2)),
      ),
    );

    final destructive = tester.getRect(find.text('删除'));
    final primary = tester.getRect(find.text('保存'));
    expect(primary.top, greaterThanOrEqualTo(destructive.bottom));
    expect(primary.center.dx, greaterThan(280));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows FxButton 不注入 Android 按钮排版', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      buildFxTestHost(
        home: Scaffold(
          body: Column(
            children: [
              FxButton(label: '保存', onPressed: () {}),
              FxButton(
                label: '重置',
                size: FxButtonSize.sm,
                variant: FxButtonVariant.ghost,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.widget<Text>(find.text('保存')).style, isNull);
    expect(tester.widget<Text>(find.text('重置')).style, isNull);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android FxButton 使用 Android 主要操作字号', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      buildFxTestHost(
        home: Scaffold(body: FxButton(label: '保存', onPressed: () {})),
      ),
    );

    final style = tester.widget<Text>(find.text('保存')).style;
    expect(style?.fontSize, SlowlightTypography.buttonSize);
    expect(style?.fontWeight, FontWeight.w600);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
