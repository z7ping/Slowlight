import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('FxTimePicker 中文界面使用时分秒标签', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: Builder(
          builder: (context) => Scaffold(
            body: FxButton(
              label: '选择时间',
              onPressed: () => showFxTimePicker(
                context: context,
                initialTime: const TimeOfDay(hour: 9, minute: 30),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('选择时间'));
    await tester.pumpAndSettle();

    expect(find.text('时'), findsOneWidget);
    expect(find.text('分'), findsOneWidget);
    expect(find.text('秒'), findsOneWidget);
    expect(find.text('Hours'), findsNothing);
    expect(find.text('Minutes'), findsNothing);
    expect(find.text('Seconds'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await disposeFxTestHost(tester);
  });
}
