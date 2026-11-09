import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('${platform.name} 二级页头保持平台专属总高度', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        buildFxTestHost(
          home: const Scaffold(
            body: Column(
              children: [
                FxPageHeader(title: '设置'),
                Expanded(child: SizedBox.shrink()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final height = tester.getSize(find.byType(FxPageHeader)).height;
      if (platform == TargetPlatform.windows) {
        expect(height, inInclusiveRange(52, 60));
      } else {
        expect(height, greaterThanOrEqualTo(66));
      }
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }

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

  for (final scale in [1.0, 2.0]) {
    testWidgets('Android 360dp 单一设置图标与标题同行（文字缩放 ${scale}x）',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        buildFxTestHost(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: const Size(360, 800),
                textScaler: TextScaler.linear(scale),
              ),
              child: FxPageHeader(
                title: '专注',
                trailing: FxIconButton(
                  icon: Icons.settings,
                  tooltip: '专注设置',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final header = tester.getRect(find.byType(FxPageHeader));
      final title = tester.getRect(find.text('专注'));
      final settings = tester.getRect(find.byIcon(Icons.settings));
      expect((title.center.dy - settings.center.dy).abs(), lessThan(20));
      expect(settings.center.dx, greaterThan(title.center.dx));
      expect(header.height, lessThan(92));
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }

  testWidgets('Android 360dp 完整诊断日志的短文本操作与页头同行', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(buildFxTestHost(
      theme: AppTheme.lightTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: FxPageHeader(
            title: '完整诊断日志',
            trailing: FxButton(
              label: '复制全部',
              size: FxButtonSize.sm,
              variant: FxButtonVariant.outline,
              onPressed: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    final title = tester.getRect(find.text('完整诊断日志'));
    final action = tester.getRect(find.text('复制全部'));
    final header = tester.getRect(find.byType(FxPageHeader));
    expect((title.center.dy - action.center.dy).abs(), lessThan(20));
    expect(action.center.dx, greaterThan(title.center.dx));
    expect(header.height, lessThan(92));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 360dp 130% 字体的诊断页头操作不溢出', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(buildFxTestHost(
      theme: AppTheme.lightTheme(),
      home: Scaffold(body: SizedBox(
        width: 360,
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(1.3),
          ),
          child: FxPageHeader(
            title: '完整诊断日志',
            trailing: FxButton(
              label: '复制全部',
              size: FxButtonSize.sm,
              onPressed: () {},
            ),
          ),
        ),
      )),
    ));
    await tester.pump();
    expect(find.text('完整诊断日志'), findsOneWidget);
    expect(find.text('复制全部'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('页头操作被禁用时仍保留图标和原有几何位置', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    Future<void> pumpHeader({required bool active}) async {
      await tester.pumpWidget(buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: FxPageHeader(
              title: '事件回调',
              actionIcon: Icons.add,
              actionTooltip: '添加事件回调',
              onAction: active ? () {} : null,
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    await pumpHeader(active: true);
    final enabledHeaderHeight = tester.getSize(find.byType(FxPageHeader)).height;
    final enabledIcon = tester.getRect(find.byIcon(Icons.add));

    await pumpHeader(active: false);
    final disabledHeaderHeight = tester.getSize(find.byType(FxPageHeader)).height;
    final disabledIcon = tester.getRect(find.byIcon(Icons.add));
    expect(disabledHeaderHeight, enabledHeaderHeight);
    expect(disabledIcon.center, enabledIcon.center);
    final disabledButton = tester.widget<FxIconButton>(
      find.ancestor(of: find.byIcon(Icons.add), matching: find.byType(FxIconButton)),
    );
    expect(disabledButton.onPressed, isNull);
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

  testWidgets('Windows FxPageHeader 使用高保真二级页头字号', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: const Scaffold(body: FxPageHeader(title: '测试页头')),
      ),
    );

    final text = tester.widget<Text>(find.text('测试页头'));
    expect(
      text.style?.fontSize,
      SlowlightTypography.desktopSecondaryPageTitleSize,
    );
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows FxPageHeader 把右侧操作稳定锚定到页头右侧', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 720,
              child: FxPageHeader(
                title: 'AI 服务',
                onBack: () {},
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
    );

    final action = tester.getRect(find.text('保存'));
    expect(action.right, greaterThan(680));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
