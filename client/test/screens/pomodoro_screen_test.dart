import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/pomodoro_screen.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('14 Android 360dp/200% 字体的刻度盘自适应且文字不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildFxTestHost(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: const PomodoroScreen(),
    ));
    await tester.pump();

    final dial = tester.widget<SizedBox>(
      find.byKey(const ValueKey('pomodoro-dial')),
    );
    expect(dial.width, lessThanOrEqualTo(312));
    expect(dial.width, greaterThan(220));
    expect(dial.width, dial.height);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

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
