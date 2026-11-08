import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  for (final variant in FxButtonVariant.values) {
    for (final size in FxButtonSize.values) {
      testWidgets('Android $variant / $size 的 ShadButton 实际命中区域至少 44dp',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        var taps = 0;
        await tester.pumpWidget(buildFxTestHost(
          home: Scaffold(
            body: Center(
              child: FxButton(
                label: '操作',
                variant: variant,
                size: size,
                onPressed: () => taps++,
              ),
            ),
          ),
        ));
        await tester.pump();
        final surface = find.descendant(
          of: find.byType(FxButton),
          matching: find.byType(ShadButton),
        );
        expect(surface, findsOneWidget);
        final rect = tester.getRect(surface);
        expect(rect.height, greaterThanOrEqualTo(44));
        // 验证实际按钮边缘能点中，而非父层只撑出不可点击的空白。
        await tester.tapAt(Offset(rect.center.dx, rect.bottom - 2));
        await tester.pump();
        expect(taps, 1);
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }
  }

  testWidgets('Android 200% 字号的按钮不被固定 44dp 裁切', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(buildFxTestHost(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: const Scaffold(
          body: Center(child: FxButton(label: '保存更改')),
        ),
      ),
    ));
    await tester.pump();
    final surface = find.descendant(
      of: find.byType(FxButton),
      matching: find.byType(ShadButton),
    );
    expect(tester.getSize(surface).height, greaterThan(44));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android dense + visualDensity 仍保留可点击列表行 44dp',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var taps = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Center(
          child: FxListTile(
            title: '紧凑操作',
            density: FxListTileDensity.compact,
            minHeight: 24,
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.zero,
            onTap: () => taps++,
          ),
        ),
      ),
    ));
    await tester.pump();
    final rect = tester.getRect(find.byType(FxListTile));
    expect(rect.height, greaterThanOrEqualTo(44));
    await tester.tapAt(Offset(rect.center.dx, rect.bottom - 2));
    await tester.pump();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows 列表继续允许桌面紧凑密度', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Center(
          child: FxListTile(
            title: '桌面操作',
            density: FxListTileDensity.compact,
            minHeight: 24,
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.zero,
            onTap: () {},
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.getSize(find.byType(FxListTile)).height, lessThan(44));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
  testWidgets('FxButton 真实禁用态不丢失 Primary 主按钮语义', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var taps = 0;
    Widget host({required bool canSave}) => buildFxTestHost(
      home: Scaffold(
        body: Center(
          child: FxButton(
            label: '保存修改',
            onPressed: canSave ? () => taps++ : null,
          ),
        ),
      ),
    );

    await tester.pumpWidget(host(canSave: false));
    await tester.pump();
    final buttonSurface = find.descendant(
      of: find.byType(FxButton),
      matching: find.byType(ShadButton),
    );
    expect(tester.widget<ShadButton>(buttonSurface).enabled, isFalse);
    expect(tester.widget<ShadButton>(buttonSurface).variant,
        ShadButtonVariant.primary);

    await tester.pumpWidget(host(canSave: true));
    await tester.pump();
    expect(tester.widget<ShadButton>(buttonSurface).enabled, isTrue);
    expect(tester.widget<ShadButton>(buttonSurface).variant,
        ShadButtonVariant.primary);
    await tester.tap(find.text('保存修改'));
    await tester.pump();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
