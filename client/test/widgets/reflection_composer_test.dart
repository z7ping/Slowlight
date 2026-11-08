import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/reflection_composer.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('X07 Windows 观察草稿取消/系统返回必须确认，且放弃确认可撤回',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '打开桌面观察',
          onPressed: () => ReflectionComposer.show(
            context, entryType: 'observation',
          ),
        ),
      )),
    ));
    await tester.tap(find.text('打开桌面观察'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '暂时不保存的观察');
    await tester.pump();

    await tester.tapAt(const Offset(3, 3));
    await tester.pump();
    expect(find.text('记录观察'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的观察？'), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(find.text('记录观察'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText).first)
          .controller.text,
      '暂时不保存的观察',
    );

    await tester.tap(find.widgetWithText(FxButton, '取消').first);
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的观察？'), findsOneWidget);
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.text('记录观察'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X07 Android 观察输入法开合后保留编辑器和焦点',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '打开观察键盘测试',
          onPressed: () => ReflectionComposer.show(
            context, entryType: 'observation',
          ),
        ),
      )),
    ));
    await tester.tap(find.text('打开观察键盘测试'));
    await tester.pumpAndSettle();
    final editable = find.byType(EditableText).first;
    await tester.tap(editable);
    await tester.enterText(editable, '键盘弹出仍保留观察草稿');
    final input = tester.widget<EditableText>(editable);
    final controller = input.controller;
    final focusNode = input.focusNode;

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(editable).controller, same(controller));
    expect(focusNode.hasFocus, isTrue);
    expect(controller.text, '键盘弹出仍保留观察草稿');
    expect(find.widgetWithText(FxButton, '保存观察'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(editable).controller, same(controller));
    expect(focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 360dp 观察 Sheet 引导线和底部操作与原型几何一致',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '打开观察',
          onPressed: () => ReflectionComposer.show(
            context,
            entryType: 'observation',
          ),
        ),
      )),
    ));
    await tester.tap(find.text('打开观察'));
    await tester.pumpAndSettle();

    final handle = find.byKey(const ValueKey('fx.sheet.dragHandle'));
    final title = find.byKey(const ValueKey('observation.mobile.title'));
    final cancel = find.byKey(const ValueKey('observation.mobile.cancel'));
    final save = find.widgetWithText(FxButton, '保存观察');
    expect(handle, findsOneWidget);
    expect(title, findsOneWidget);
    expect(cancel, findsOneWidget);
    expect(save, findsOneWidget);
    expect(tester.getSize(handle).height, 44);
    expect(
      tester.getTopLeft(title).dy >= tester.getBottomLeft(handle).dy,
      isTrue,
    );
    expect(
      (tester.getSize(cancel).width - tester.getSize(save).width).abs(),
      lessThan(1.0),
    );
    expect(tester.getSize(cancel).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(save).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 今天记录观察与原型的字段和草稿退出流程一致',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 880);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Builder(builder: (context) => FxButton(
          label: '记录观察',
          onPressed: () async {
            await ReflectionComposer.show(
              context,
              entryType: 'observation',
              contextData: const {'source': 'today'},
            );
          },
        )),
      ),
    ));
    await tester.tap(find.text('记录观察'));
    await tester.pumpAndSettle();

    expect(find.text('归属维度（可选）'), findsOneWidget);
    expect(find.byKey(const ValueKey('observation.mobile.dimensions')),
        findsOneWidget);
    expect(find.text('历史观察分类（兼容）'), findsNothing);
    expect(find.text('标签（可选）'), findsOneWidget);
    expect(find.text('＋ 新建标签'), findsOneWidget);

    await tester.tap(find.text('＋ 新建标签'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('observation.mobile.tagName')),
        findsOneWidget);

    await tester.enterText(
      find.byType(EditableText).first,
      '今天留意到自己的注意力变化',
    );
    await tester.tap(find.byKey(const ValueKey('observation.mobile.cancel')));
    await tester.pumpAndSettle();

    expect(find.text('放弃未保存的观察？'), findsOneWidget);
    expect(find.text('放弃修改'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X07 Windows 提供四维选择且不依赖历史分类标签', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '打开四维观察',
          onPressed: () => ReflectionComposer.show(
            context, entryType: 'observation',
          ),
        ),
      )),
    ));
    await tester.tap(find.text('打开四维观察'));
    await tester.pumpAndSettle();
    final dimensions =
        find.byKey(const ValueKey('observation.desktop.dimensions'));
    expect(dimensions, findsOneWidget);
    expect(find.descendant(of: dimensions, matching: find.byType(FxChoiceChip)),
        findsNWidgets(5));
    expect(find.text('归属维度（可选）'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('X07 Android 仅填写新标签名也是需要确认的观察草稿', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: Builder(
        builder: (context) => FxButton(
          label: '打开新标签观察',
          onPressed: () => ReflectionComposer.show(
            context, entryType: 'observation',
          ),
        ),
      )),
    ));
    await tester.tap(find.text('打开新标签观察'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('＋ 新建标签'));
    await tester.pumpAndSettle();
    final tagName = find.byKey(const ValueKey('observation.mobile.tagName'));
    expect(tagName, findsOneWidget);
    await tester.enterText(find.descendant(
      of: tagName, matching: find.byType(EditableText)), '专注片刻');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('observation.mobile.cancel')));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的观察？'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
