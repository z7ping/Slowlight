import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/reminder_screen.dart';
import 'package:slowlight/services/reminder_service.dart';
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
  group('ReminderScreen 稳定契约', () {
    testWidgets('开始工作后服务进入 working 状态', (tester) async {
      final service = ReminderService();
      await tester.pumpWidget(buildHost(const ReminderScreen()));
      await tester.pump();

      await tester.tap(find.text('开始工作'));
      await tester.pump();

      expect(service.state, 'working');

      service.stopAll();
      await tester.pump();
      expect(service.state, 'idle');
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

        await tester.pumpWidget(buildHost(const ReminderScreen()));
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('快速销毁时异步状态不会导致异常', (tester) async {
      await tester.pumpWidget(buildHost(const ReminderScreen()));
      await tester.pump();
      await tester.pumpWidget(buildHost(const Scaffold()));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
