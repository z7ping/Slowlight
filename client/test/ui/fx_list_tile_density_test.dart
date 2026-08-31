import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('FxListTile 语义密度保持既定行高层级', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: const Scaffold(
          body: Column(
            children: [
              FxListTile(
                key: ValueKey('sidebar'),
                title: '侧栏',
                density: FxListTileDensity.sidebar,
                padding: EdgeInsets.zero,
              ),
              FxListTile(
                key: ValueKey('compact'),
                title: '紧凑',
                density: FxListTileDensity.compact,
                padding: EdgeInsets.zero,
              ),
              FxListTile(
                key: ValueKey('standard'),
                title: '标准',
                density: FxListTileDensity.standard,
                padding: EdgeInsets.zero,
              ),
              FxListTile(
                key: ValueKey('detailed'),
                title: '详细',
                subtitle: '带副标题',
                density: FxListTileDensity.detailed,
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const ValueKey('sidebar'))).height, 44);
    expect(tester.getSize(find.byKey(const ValueKey('compact'))).height, 44);
    expect(tester.getSize(find.byKey(const ValueKey('standard'))).height, 52);
    expect(tester.getSize(find.byKey(const ValueKey('detailed'))).height, 58);
    expect(tester.takeException(), isNull);

    await disposeFxTestHost(tester);
  });
}
