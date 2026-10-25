import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  for (final spec in <(Size, double, double)>[
    (const Size(360, 800), SlowlightSpacing.xxxl, SlowlightSpacing.xxxl),
    (const Size(1280, 800), SlowlightSpacing.page, 20),
  ]) {
    testWidgets('普通窗口 ${spec.$1.width}dp 下页面左右留白一致',
        (tester) async {
      tester.view.physicalSize = spec.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      late EdgeInsets insets;
      await tester.pumpWidget(buildFxTestHost(
        home: Builder(
          builder: (context) {
            insets = SlowlightPageInsets.scroll(
              context,
              bottom: SlowlightSpacing.page,
            );
            return const SizedBox.shrink();
          },
        ),
      ));

      expect(insets.left, spec.$2);
      expect(insets.right, spec.$2);
      expect(insets.top, spec.$3);
      expect(insets.bottom, SlowlightSpacing.page);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }
}
