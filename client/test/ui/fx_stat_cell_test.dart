import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/app_theme.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('Windows FxStatCell 恢复 Fx 化前统计主数值层级', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: const Scaffold(
          body: FxStatCell(
            value: '128',
            suffix: ' 分钟',
            label: '本周专注时长',
          ),
        ),
      ),
    );

    final richText = tester.widget<Text>(find.textContaining('128'));
    final span = richText.textSpan! as TextSpan;
    expect(span.style?.fontSize, SlowlightTypography.desktopStatValueSize);
    expect(span.style?.fontWeight, FontWeight.w700);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android FxStatCell 保持 20px 数据强调层级', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: const Scaffold(
          body: FxStatCell(
            value: '128',
            suffix: ' 分钟',
            label: '本周专注时长',
          ),
        ),
      ),
    );

    final richText = tester.widget<Text>(find.textContaining('128'));
    final span = richText.textSpan! as TextSpan;
    expect(span.style?.fontSize, SlowlightTypography.pageTitleSize);
    await disposeFxTestHost(tester);
  });

  testWidgets('FxStatCell 在 360dp + 200% 字体缩放下保持可读', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: const Scaffold(
            body: SizedBox(
              width: 180,
              child: FxStatCell(
                value: '128',
                suffix: ' 分钟',
                label: '本周专注时长',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('128'), findsOneWidget);
    expect(find.text('本周专注时长'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
