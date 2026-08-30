import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/pomodoro_screen.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('专注设置关闭后不会残留遮罩', (tester) async {
    await tester.pumpWidget(buildFxTestHost(home: const PomodoroScreen()));
    await tester.pump();
    final baselineBarriers = find.byType(ModalBarrier).evaluate().length;

    await tester.tap(fxTooltipFinder('专注设置'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(
      find.byType(ModalBarrier).evaluate().length,
      baselineBarriers,
    );
    await disposeFxTestHost(tester);
  });
}
