import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  Widget grid() => Center(
    child: SizedBox(
      width: 560,
      child: FxResponsiveFormGrid(
        minColumnWidth: 240,
        children: const [
          SizedBox(key: Key('first'), height: 44),
          SizedBox(key: Key('second'), height: 44),
        ],
      ),
    ),
  );

  testWidgets('FxResponsiveFormGrid 在 560dp + 130% 字体下保持双列', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildFxTestHost(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(body: grid()),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(const Key('first'))).dy,
      tester.getTopLeft(find.byKey(const Key('second'))).dy,
    );
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('FxResponsiveFormGrid 在 560dp + 200% 字体下自然退化单列', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildFxTestHost(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: grid()),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(const Key('second'))).dy,
      greaterThan(tester.getTopLeft(find.byKey(const Key('first'))).dy),
    );
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
