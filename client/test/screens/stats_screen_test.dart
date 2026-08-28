import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/stats_screen.dart';

void main() {
  group('StatsScreen', () {
    group('桌面端嵌入约束（Expanded > Column > body）', () {
      testWidgets('宽屏 > 800px 不崩溃', (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  const SizedBox(width: 260),
                  Expanded(
                    child: Column(
                      children: [
                        const SizedBox(height: 56),
                        const Expanded(child: StatsScreen()),
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(StatsScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('窄屏 400px 不崩溃', (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const SizedBox(height: 56),
                  const Expanded(child: StatsScreen()),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(StatsScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    group('Navigator.push 路径', () {
      testWidgets('推送后有 Scaffold 包裹', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Material(child: StatsScreen()),
          ),
        );
        await tester.pump();
        expect(find.byType(StatsScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    group('基础渲染', () {
      testWidgets('渲染不崩溃', (tester) async {
        await tester
            .pumpWidget(const MaterialApp(home: Scaffold(body: StatsScreen())));
        await tester.pump();
        expect(find.byType(StatsScreen), findsOneWidget);
      });

      testWidgets('多次 pump 不崩溃', (tester) async {
        await tester
            .pumpWidget(const MaterialApp(home: Scaffold(body: StatsScreen())));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(StatsScreen), findsOneWidget);
      });
    });

    group('多屏幕尺寸', () {
      for (final size in [
        const Size(375, 667),
        const Size(414, 896),
        const Size(768, 1024),
        const Size(1200, 800),
        const Size(1920, 1080),
      ]) {
        testWidgets('${size.width.toInt()}×${size.height.toInt()} 不崩溃',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            const MaterialApp(home: Scaffold(body: StatsScreen())),
          );
          await tester.pump();
          expect(find.byType(StatsScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    });
  });
}
