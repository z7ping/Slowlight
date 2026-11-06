import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/reflection_composer.dart';

import '../support/fx_test_host.dart';

void main() {
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
          onPressed: () => ReflectionComposer.show(
            context,
            entryType: 'observation',
            contextData: const {'source': 'today'},
          ),
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
