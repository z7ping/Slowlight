import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:slowlight/screens/pomodoro_screen.dart';
import 'package:slowlight/ui/theme_manager.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget buildHost(Widget home) {
  return ShadTheme(
    data: ThemeManager.shadLight,
    child: MaterialApp(
      theme: ThemeManager.lightTheme,
      home: home,
    ),
  );
}

void main() {
  group('PomodoroScreen', () {
    group('UI 渲染', () {
      testWidgets('渲染不崩溃', (tester) async {
        await tester.pumpWidget(buildHost(const PomodoroScreen()));
        await tester.pump();
        expect(find.byType(PomodoroScreen), findsOneWidget);
      });

      testWidgets('显示返回按钮', (tester) async {
        await tester.pumpWidget(buildHost(const PomodoroScreen()));
        await tester.pump();
        expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);
      });

      testWidgets('显示计时器数字', (tester) async {
        await tester.pumpWidget(buildHost(const PomodoroScreen()));
        await tester.pump();
        expect(find.text('25:00'), findsOneWidget);
      });

      testWidgets('专注设置关闭后不会残留遮罩', (tester) async {
        await tester.pumpWidget(buildHost(const PomodoroScreen()));
        await tester.pump();
        final baselineBarriers = find.byType(ModalBarrier).evaluate().length;

        await tester.tap(find.byTooltip('专注设置'));
        await tester.pumpAndSettle();
        expect(find.text('🍅 专注设置'), findsOneWidget);

        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(find.text('🍅 专注设置'), findsNothing);
        expect(
          find.byType(ModalBarrier).evaluate().length,
          baselineBarriers,
        );
      });
    });
  });
}
