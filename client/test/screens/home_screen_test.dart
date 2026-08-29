import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/home_screen.dart';
import 'package:slowlight/screens/quadrant_screen.dart';
import 'package:slowlight/ui/theme_manager.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  Widget buildApp() {
    return ShadTheme(
      data: ThemeManager.shadLight,
      child: MaterialApp(
        theme: ThemeManager.lightTheme,
        home: const HomeScreen(),
      ),
    );
  }

  Future<void> pumpAt(
    WidgetTester tester, {
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    await tester.pump();
  }

  group('HomeScreen 稳定契约', () {
    for (final size in [
      const Size(500, 844),
      const Size(1200, 800),
    ]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()} 主壳不产生布局异常',
          (tester) async {
        await pumpAt(tester, size: size);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('四象限入口可以进入实际功能页', (tester) async {
      await pumpAt(tester, size: const Size(1200, 800));

      await tester.tap(find.text('四象限'));
      await tester.pump();

      expect(find.byType(QuadrantScreen), findsOneWidget);
    });
  });
}
