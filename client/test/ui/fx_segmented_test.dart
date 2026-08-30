import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/app_theme.dart';
import 'package:slowlight/ui/fx.dart';

void main() {
  testWidgets('FxSegmented 在 360dp + 200% 字体缩放下可用', (tester) async {
    var selected = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Align(
                alignment: Alignment.topLeft,
                child: FxSegmented(
                  labels: const ['全部', '进行中', '已完成'],
                  selectedIndex: selected,
                  onChanged: (index) => setState(() => selected = index),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('已完成'));
    await tester.pump();
    expect(selected, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FxSegmented 使用辅助信息语义字号', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: FxSegmented(
            labels: const ['A', 'B'],
            selectedIndex: 0,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('A'));
    expect(text.style?.fontSize, SlowlightTypography.secondarySize);
    expect(text.style?.height, closeTo(20 / 14, 0.0001));
  });

  testWidgets('FxSegmented 展开时等分可用宽度', (tester) async {
    final keys = List.generate(3, (index) => ValueKey('segment-$index'));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: FxSegmented(
                labels: const ['概览', '统计', '时间分配'],
                selectedIndex: 0,
                onChanged: (_) {},
                itemKeys: keys,
                expanded: true,
              ),
            ),
          ),
        ),
      ),
    );

    final widths = keys.map((key) => tester.getSize(find.byKey(key)).width);
    expect(tester.getSize(find.byType(FxSegmented)).width, 320);
    expect(widths.every((width) => width > 100), isTrue);
    expect(
        widths.reduce((a, b) => a > b ? a : b) -
            widths.reduce((a, b) => a < b ? a : b),
        lessThan(0.01));
  });
}
