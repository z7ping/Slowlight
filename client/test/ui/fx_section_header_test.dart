import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/app_theme.dart';
import 'package:slowlight/ui/fx.dart';

void main() {
  testWidgets('FxSectionHeader 使用统一标题与辅助信息排版', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
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
    expect(title.style?.fontSize, SlowlightTypography.cardTitleSize);
    expect(trailing.style?.fontSize, SlowlightTypography.secondarySize);
  });

  testWidgets('FxSectionHeader 在 360dp + 200% 字体缩放下不溢出', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
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
  });
}
