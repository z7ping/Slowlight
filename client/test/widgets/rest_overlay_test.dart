import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/rest_overlay.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('严格小憩遮罩恢复高保真结构且隐藏跳过入口', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: const RestOverlay(
          isMicroRest: true,
          restSeconds: 20,
          strict: true,
          allowPostpone: false,
        ),
      ),
    );

    expect(find.text('MICRO BREAK'), findsOneWidget);
    expect(find.byType(FxProgressRing), findsOneWidget);
    expect(find.text('严格模式 · 不可跳过'), findsOneWidget);
    expect(find.text('跳过'), findsNothing);
    expect(tester.takeException(), isNull);

    await disposeFxTestHost(tester);
  });

  testWidgets('非严格长休息保留弱化跳过与延后入口', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: const RestOverlay(
          isMicroRest: false,
          restSeconds: 300,
          strict: false,
          allowPostpone: true,
        ),
      ),
    );

    expect(find.text('LONG BREAK'), findsOneWidget);
    expect(find.text('延后 5 分钟'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);
    expect(find.text('严格模式 · 不可跳过'), findsNothing);
    expect(tester.takeException(), isNull);

    await disposeFxTestHost(tester);
  });
}
