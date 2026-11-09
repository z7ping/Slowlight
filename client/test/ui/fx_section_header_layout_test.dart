import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  Widget section(double width, double scale) => Center(
        child: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(scale),
          ),
          child: SizedBox(
            width: width,
            child: FxSectionHeader(
              title: '同步状态',
              trailingWidget: FxButton(
                label: '立即同步',
                size: FxButtonSize.sm,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

  for (final width in [320.0, 360.0, 393.0]) {
    testWidgets('FxSectionHeader ${width}dp 130% 短操作仍同行', (tester) async {
      await tester.pumpWidget(
        buildFxTestHost(home: Scaffold(body: section(width, 1.3))),
      );
      final title = tester.getRect(find.text('同步状态'));
      final action = tester.getRect(find.text('立即同步'));
      expect((title.center.dy - action.center.dy).abs(), lessThan(24));
      expect(action.right, lessThanOrEqualTo(width + 1));
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }

  testWidgets('FxSectionHeader 空间真实不足才将操作下移', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(home: Scaffold(body: section(160, 2))),
    );
    final title = tester.getRect(find.text('同步状态'));
    final action = tester.getRect(find.text('立即同步'));
    expect(action.top, greaterThanOrEqualTo(title.bottom));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
