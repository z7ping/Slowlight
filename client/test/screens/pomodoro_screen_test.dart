import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  testWidgets('专注设置关闭后不会残留遮罩', (tester) async {
    await tester.pumpWidget(buildHost(const PomodoroScreen()));
    await tester.pump();
    final baselineBarriers = find.byType(ModalBarrier).evaluate().length;

    await tester.tap(find.byTooltip('专注设置'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(
      find.byType(ModalBarrier).evaluate().length,
      baselineBarriers,
    );
  });
}
