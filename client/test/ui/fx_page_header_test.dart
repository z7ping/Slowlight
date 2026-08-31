import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/app_theme.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('FxPageHeader 在真实 360dp + 200% 字体下保持可用', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: Center(
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(2),
              ),
              child: const SizedBox(
                width: 360,
                child: FxPageHeader(
                  title: '这是一个用于验证大字体布局的较长页面标题',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('这是一个用于验证大字体布局的较长页面标题'), findsOneWidget);
    expect(find.byType(FxIconButton), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('FxPageHeader 大字体时右侧动作下移并保持右对齐', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: Center(
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(2),
              ),
              child: SizedBox(
                width: 360,
                child: FxPageHeader(
                  title: '任务详情',
                  trailing: FxButton(
                    label: '保存',
                    size: FxButtonSize.sm,
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final title = tester.getRect(find.text('任务详情'));
    final action = tester.getRect(find.text('保存'));
    expect(action.top, greaterThanOrEqualTo(title.bottom));
    expect(action.center.dx, greaterThan(240));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android FxPageHeader 使用页面标题可读字号', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: const Scaffold(body: FxPageHeader(title: '测试页头')),
      ),
    );

    final text = tester.widget<Text>(find.text('测试页头'));
    expect(text.style?.fontSize, SlowlightTypography.pageTitleSize);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows FxPageHeader 保持既有桌面标题密度', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: const Scaffold(body: FxPageHeader(title: '测试页头')),
      ),
    );

    final text = tester.widget<Text>(find.text('测试页头'));
    expect(text.style?.fontSize, SlowlightTypography.desktopPageTitleSize);
    await disposeFxTestHost(tester);
  });
}
