import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/time_distribution_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('P13 刷新失败保留已确认的时间分配与原位重试', (tester) async {
    var reads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TimeDistributionScreen(
        dataLoader: () async {
          if (++reads == 1) {
            return {
              'total_min': 90,
              'tags': <Map<String, dynamic>>[
                {'name': '深度工作', 'total_min': 90, 'percent': 100},
              ],
              'by_day': <Map<String, dynamic>>[],
            };
          }
          throw StateError('read failed');
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('深度工作'), findsOneWidget);
    await tester.widget<FxRefresh>(find.byType(FxRefresh)).onRefresh();
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('深度工作'), findsOneWidget);
    expect(find.text('时间分配刷新未确认，以下为上次已载入记录。'),
        findsOneWidget);
    expect(find.text('时间分配暂时不可用'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P13 迟到的旧刷新结果不能覆盖最新时间分配', (tester) async {
    final old = Completer<Map<String, dynamic>>();
    final latest = Completer<Map<String, dynamic>>();
    var reads = 0;
    Map<String, dynamic> data(String name) => {
      'total_min': 30,
      'tags': <Map<String, dynamic>>[
        {'name': name, 'total_min': 30, 'percent': 100},
      ],
      'by_day': <Map<String, dynamic>>[],
    };
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TimeDistributionScreen(
        dataLoader: () {
          if (++reads == 1) return Future.value(data('初始分类'));
          if (reads == 2) return old.future;
          return latest.future;
        },
      )),
    ));
    await tester.pumpAndSettle();
    final refresh = tester.widget<FxRefresh>(find.byType(FxRefresh));
    final stale = refresh.onRefresh();
    final newer = refresh.onRefresh();
    await tester.pump();
    expect(find.text('初始分类'), findsOneWidget);
    latest.complete(data('最新分类'));
    await newer;
    await tester.pump();
    old.complete(data('过期分类'));
    await stale;
    await tester.pumpAndSettle();
    expect(find.text('最新分类'), findsOneWidget);
    expect(find.text('过期分类'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P13 有专注分钟但没有标签不展示暂无专注', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TimeDistributionScreen(
        dataLoader: () async => {
          'total_min': 50,
          'tags': <Map<String, dynamic>>[],
          'by_day': <Map<String, dynamic>>[],
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('当前专注尚无可确认的分类'), findsOneWidget);
    expect(find.text('暂无专注数据'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });


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
