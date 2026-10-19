import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/time_distribution_screen.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('03 时间分配错误状态可重试，成功后使用统一标签术语', (tester) async {
    var attempts = 0;
    Future<Map<String, dynamic>> load() async {
      attempts++;
      if (attempts == 1) throw StateError('offline');
      return {
        'total_min': 0,
        'tags': <Map<String, dynamic>>[],
        'by_day': <Map<String, dynamic>>[],
      };
    }

    await tester.pumpWidget(
      buildFxTestHost(
        home: Scaffold(
          body: TimeDistributionScreen(dataLoader: load),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('时间分配暂时不可用'), findsOneWidget);
    expect(find.text('暂无专注数据'), findsNothing);

    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('标签分布'), findsOneWidget);
    expect(find.text('时间分配暂时不可用'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
