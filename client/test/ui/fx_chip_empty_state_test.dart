import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/app_theme.dart';
import 'package:slowlight/ui/fx.dart';

void main() {
  testWidgets('FxChip 在 360dp + 200% 字体缩放下保持可用', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: const Scaffold(
            body: Center(
              child: FxChip(
                label: '这是一个较长的状态标签',
                backgroundColor: Color(0xFFF4F4F5),
                foregroundColor: Color(0xFF52525B),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('这是一个较长的状态标签'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FxEmptyState 在 360dp + 200% 字体缩放下保持可读', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: const Scaffold(
            body: FxEmptyState(
              emoji: '✨',
              title: '暂时没有内容',
              subtitle: '完成第一条记录后，这里会展示你的长期变化。',
            ),
          ),
        ),
      ),
    );

    expect(find.text('暂时没有内容'), findsOneWidget);
    expect(find.text('完成第一条记录后，这里会展示你的长期变化。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
