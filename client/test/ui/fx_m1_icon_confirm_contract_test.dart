import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final variant in FxIconButtonVariant.values) {
      testWidgets('FxIconButton $platform / $variant 使用对应平台的真实按钮尺寸',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        var taps = 0;
        await tester.pumpWidget(buildFxTestHost(
          home: Scaffold(
            body: Center(
              child: FxIconButton(
                icon: Icons.close,
                variant: variant,
                onPressed: () => taps++,
              ),
            ),
          ),
        ));
        await tester.pump();

        final surface = find.byType(ShadIconButton);
        expect(surface, findsOneWidget);
        final button = tester.widget<ShadIconButton>(surface);
        if (platform == TargetPlatform.android) {
          expect(button.width, 44);
          expect(button.height, 44);
          final rect = tester.getRect(surface);
          expect(rect.width, greaterThanOrEqualTo(44));
          expect(rect.height, greaterThanOrEqualTo(44));
          await tester.tapAt(Offset(rect.center.dx, rect.bottom - 2));
        } else {
          // Windows 仍使用原有 28dp 内容尺寸，不反向扩大桌面控件。
          expect(button.width, 28);
          expect(button.height, 28);
          await tester.tap(surface);
        }
        await tester.pump();
        expect(taps, 1);
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }
  }

  for (final destructive in [false, true]) {
    for (final confirm in [false, true]) {
      testWidgets('Android 统一确认弹窗 destructive=$destructive confirm=$confirm',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        Future<bool?>? result;
        await tester.pumpWidget(buildFxTestHost(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  result = FxDialog.confirm(
                    context: context,
                    title: '确认操作',
                    content: '这是一项需要确认的操作。',
                    destructive: destructive,
                    confirmText: '确定',
                    cancelText: '取消',
                  );
                },
                child: const Text('打开确认'),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('打开确认'));
        await tester.pumpAndSettle();

        final buttons = find.descendant(
          of: find.byType(ShadDialog),
          matching: find.byType(FxButton),
        );
        expect(buttons, findsNWidgets(2));
        for (final button in tester.widgetList<FxButton>(buttons)) {
          expect(
            button.variant,
            button.label == '取消'
                ? FxButtonVariant.outline
                : destructive
                    ? FxButtonVariant.destructive
                    : FxButtonVariant.primary,
          );
        }
        final shadButtons = find.descendant(
          of: find.byType(ShadDialog),
          matching: find.byType(ShadButton),
        );
        expect(shadButtons, findsNWidgets(2));
        for (final button in shadButtons.evaluate()) {
          final rect = tester.getRect(find.byElementPredicate(
            (element) => identical(element, button),
          ));
          expect(rect.height, greaterThanOrEqualTo(44));
        }

        await tester.tap(find.text(confirm ? '确定' : '取消'));
        await tester.pumpAndSettle();
        expect(await result, confirm);
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }
  }
}
