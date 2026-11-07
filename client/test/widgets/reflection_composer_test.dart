import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/reflection_composer.dart';

import '../support/fx_test_host.dart';

void main() {
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
}
