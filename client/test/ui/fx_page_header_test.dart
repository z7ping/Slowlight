import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:slowlight/ui/app_theme.dart';
import 'package:slowlight/ui/fx.dart';

Widget _testApp(Widget child) {
  return ShadTheme(
    data: shadLightTheme(null),
    child: MaterialApp(
      theme: AppTheme.lightTheme(),
      home: child,
    ),
  );
}

void main() {
  testWidgets('FxPageHeader 在 360dp + 200% 字体缩放下保持可用', (tester) async {
    await tester.pumpWidget(
      _testApp(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: const Scaffold(
            body: FxPageHeader(
              title: '这是一个用于验证大字体布局的较长页面标题',
            ),
          ),
        ),
      ),
    );

    expect(find.text('这是一个用于验证大字体布局的较长页面标题'), findsOneWidget);
    expect(find.byType(FxIconButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FxPageHeader 标题使用页面标题语义字号', (tester) async {
    await tester.pumpWidget(
      _testApp(const Scaffold(body: FxPageHeader(title: '测试页头'))),
    );

    final text = tester.widget<Text>(find.text('测试页头'));
    expect(text.style?.fontSize, SlowlightTypography.pageTitleSize);
  });
}
