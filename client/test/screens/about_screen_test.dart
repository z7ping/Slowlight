import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:slowlight/screens/about_screen.dart';
import 'package:slowlight/services/app_info_service.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('S19 版本读取失败不能一直显示读取中，重试后显示真实版本', (tester) async {
    var loads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: AboutScreen(
          serverInfoLoader: () async => const ServerVersionInfo(
            version: '0.2.1',
            commitHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
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
  testWidgets('版本信息显示 APK 和真实服务端元数据，失败可独立重查', (tester) async {
    var requests = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: AboutScreen(
          infoLoader: () async => PackageInfo(
            appName: 'Slowlight',
            packageName: 'site.z7ping.slowlight',
            version: '1.0.0',
            buildNumber: '5',
          ),
          serverInfoLoader: () async {
            if (++requests == 1) throw StateError('offline');
            return const ServerVersionInfo(
              version: '2.0.0',
              deployedAt: '2026-11-08T05:00:00Z',
              commitTime: '2026-11-07T10:00:00Z',
              commitHash: '1234567890123456789012345678901234567890',
            );
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1.0.0+5'), findsOneWidget);
    expect(find.text('查询失败'), findsOneWidget);
    expect(find.text('未确认'), findsWidgets);
    expect(find.text('重新查询服务端版本'), findsOneWidget);

    await tester.tap(find.text('重新查询服务端版本'));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(find.text('2.0.0'), findsOneWidget);
    expect(find.text('1234567890123456789012345678901234567890'), findsOneWidget);
    expect(find.text('查询失败'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
