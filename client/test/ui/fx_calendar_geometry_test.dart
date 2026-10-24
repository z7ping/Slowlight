import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });
  for (final scale in [1.3, 2.0]) {
    testWidgets('Android 日历星期在 $scale 倍字体完整显示且日期可选', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      DateTime? selected;
      await tester.pumpWidget(buildFxTestHost(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
            body: FxCalendar<Object>(
          firstDay: DateTime(2026),
          lastDay: DateTime(2027),
          focusedDay: DateTime(2026, 10, 24),
          eventLoader: (_) => const [],
          onDaySelected: (day, _) {
            selected = day;
          },
        )),
      ));
      await tester.pump();
      final weekday = find.text('周一');
      final text = tester.widget<Text>(weekday);
      final painter = TextPainter(
        text: TextSpan(text: text.data, style: text.style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(scale),
      )..layout();
      expect(
          tester.getSize(weekday).height, greaterThanOrEqualTo(painter.height));
      painter.dispose();
      await tester.tap(find.text('24'));
      await tester.pump();
      expect(selected, DateTime.utc(2026, 10, 24));
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }
}
