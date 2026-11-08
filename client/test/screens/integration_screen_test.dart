import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/integration_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('12 平台集成复用 Fx 二级页头', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: const IntegrationScreen(),
    ));
    expect(find.byType(FxPageHeader), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('飞书多维表格'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('S15 只有飞书入口可执行，未开放平台保持不可点击', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      home: const IntegrationScreen(),
    ));
    final feishu = find.ancestor(
      of: find.text('飞书多维表格'),
      matching: find.byType(FxCard),
    );
    final notion = find.ancestor(
      of: find.text('Notion'),
      matching: find.byType(FxCard),
    );
    expect(feishu, findsOneWidget);
    expect(notion, findsOneWidget);
    expect(tester.widget<FxCard>(feishu).onTap, isNotNull);
    expect(tester.widget<FxCard>(notion).onTap, isNull);
    expect(find.text('尚未开放'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
