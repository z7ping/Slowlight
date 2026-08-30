import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/app_theme.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('FxSectionHeader 使用高密度分区标题与辅助信息排版', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: const Scaffold(
          body: FxSectionHeader(
            title: '今日任务',
            trailing: '3/5 已完成',
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('今日任务'));
    final trailing = tester.widget<Text>(find.text('3/5 已完成'));
    expect(title.style?.fontSize, SlowlightTypography.secondarySize);
    expect(trailing.style?.fontSize, SlowlightTypography.captionSize);
    await disposeFxTestHost(tester);
  });

  testWidgets('FxSectionHeader 在 360dp + 200% 字体缩放下不溢出', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: FxSectionHeader(
                title: '这是一个较长的分区标题',
                trailing: '这是较长的辅助状态信息',
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('FxSectionHeader 大字体时将查看全部放到下一行右侧', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: FxSectionHeader(
                title: '今日任务',
                trailing: '3/5 已完成',
                trailingWidget: FxButton(
                  label: '查看全部',
                  variant: FxButtonVariant.ghost,
                  size: FxButtonSize.sm,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final titleBottom = tester.getBottomLeft(find.text('今日任务')).dy;
    final actionTop = tester.getTopLeft(find.text('查看全部')).dy;
    expect(actionTop, greaterThanOrEqualTo(titleBottom));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
