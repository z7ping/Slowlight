import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/ui/layout_tokens.dart';

import '../support/fx_test_host.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    group('Fx 表单尺寸契约 $platform', () {
      testWidgets('普通输入、带尾部控件输入及下拉框最低高度统一', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        await tester.pumpWidget(buildFxTestHost(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FxInput(placeholder: '普通字段'),
                    const FxInput(
                      placeholder: '密码',
                      trailing: Icon(Icons.visibility, size: 18),
                    ),
                    FxSelect<String>(
                      value: 'a',
                      options: const [
                        FxSelectOption(value: 'a', label: '选项一'),
                        FxSelectOption(value: 'b', label: '选项二'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ));
        await tester.pump();

        final normal = tester.getSize(find.byType(FxInput).at(0)).height;
        final decorated = tester.getSize(find.byType(FxInput).at(1)).height;
        final selected = tester.getSize(find.byType(FxSelect<String>)).height;
        final minimum = SlowlightPlatformDensity.inputMinHeight;

        expect(normal, greaterThanOrEqualTo(minimum));
        expect(decorated, greaterThanOrEqualTo(minimum));
        expect(selected, greaterThanOrEqualTo(minimum));
        expect(decorated, closeTo(normal, 0.1));
        expect(selected, closeTo(normal, 0.1));
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    });
  }
}
