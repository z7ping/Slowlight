import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/stats_screen.dart';

void main() {
  group('StatsScreen 响应式稳定性', () {
    for (final size in [
      const Size(400, 800),
      const Size(1200, 800),
    ]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()} 不产生布局异常',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: StatsScreen())),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
