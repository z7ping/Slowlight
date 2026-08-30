import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/reminder_screen.dart';
import 'package:slowlight/services/reminder_service.dart';

import '../support/fx_test_host.dart';

void main() {
  group('ReminderScreen 稳定契约', () {
    testWidgets('开始工作后服务进入 working 状态', (tester) async {
      final service = ReminderService();
      await tester.pumpWidget(buildFxTestHost(home: const ReminderScreen()));
      await tester.pump();

      await tester.tap(find.text('开始工作'));
      await tester.pump();

      expect(service.state, 'working');

      service.stopAll();
      await tester.pump();
      expect(service.state, 'idle');
      await disposeFxTestHost(tester);
    });

    for (final size in [
      const Size(400, 800),
      const Size(1200, 800),
    ]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()} 不产生布局异常',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(buildFxTestHost(home: const ReminderScreen()));
        await tester.pump();

        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }

    testWidgets('快速销毁时异步状态不会导致异常', (tester) async {
      await tester.pumpWidget(buildFxTestHost(home: const ReminderScreen()));
      await tester.pump();
      await disposeFxTestHost(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
