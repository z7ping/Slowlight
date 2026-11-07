import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:slowlight/screens/about_screen.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('S19 版本读取失败不能一直显示读取中，重试后显示真实版本', (tester) async {
    var loads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: AboutScreen(
          infoLoader: () async {
            if (++loads == 1) throw StateError('metadata unavailable');
            return PackageInfo(
              appName: 'Slowlight',
              packageName: 'site.z7ping.slowlight',
              version: '1.2.3',
              buildNumber: '42',
            );
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('读取失败'), findsOneWidget);
    expect(find.text('读取中…'), findsNothing);
    expect(find.text('重试读取版本'), findsOneWidget);
    expect(find.text('所行映我 · Slowlight'), findsOneWidget);

    await tester.tap(find.text('重试读取版本'));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.text('1.2.3+42'), findsOneWidget);
    expect(find.text('重试读取版本'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
