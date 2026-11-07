import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/weekly_review_screen.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

Map<String, dynamic> _week(int count) => {
  'task_completed': count,
  'habit_checked': 2,
  'focus_minutes': 60,
  'habit_last_week': 1,
  'task_last_week': 1,
  'focus_last_week': 45,
  'time_distribution': <Map<String, dynamic>>[],
};

void main() {
  testWidgets('P11 主回顾刷新失败保留旧周数据且不混入新辅助源', (tester) async {
    var reviews = 0;
    var outputs = 0;
    var trends = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: WeeklyReviewScreen(
        embedded: true,
        reviewLoader: () async {
          if (++reviews > 1) throw StateError('本周统计暂不可用');
          return _week(8);
        },
        outputStatsLoader: () async {
          outputs++;
          return {'this_week': 2, 'total_count': 2};
        },
        dailyTrendLoader: () async {
          trends++;
          return <Map<String, dynamic>>[
            {'date': '2026-11-06', 'task_completed': 8},
          ];
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(outputs, 1);
    expect(trends, 1);
    expect(find.text('8'), findsOneWidget);

    await tester.widget<FxRefresh>(find.byType(FxRefresh)).onRefresh();
    await tester.pumpAndSettle();
    expect(reviews, 2);
    expect(outputs, 1);
    expect(trends, 1);
    expect(find.text('8'), findsOneWidget);
    expect(find.textContaining('本周数据刷新未确认'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P11 主回顾成功更新时清除上一个周期的辅助数据', (tester) async {
    final pendingOutput = Completer<Map<String, dynamic>>();
    var reviews = 0;
    var outputs = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: WeeklyReviewScreen(
        embedded: true,
        reviewLoader: () async => _week(++reviews == 1 ? 8 : 3),
        outputStatsLoader: () {
          if (++outputs == 1) {
            return Future.value({'this_week': 4, 'total_count': 4});
          }
          return pendingOutput.future;
        },
        dailyTrendLoader: () async => <Map<String, dynamic>>[],
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('输出记录'), findsOneWidget);

    await tester.widget<FxRefresh>(find.byType(FxRefresh)).onRefresh();
    await tester.pump();
    expect(reviews, 2);
    expect(outputs, 2);
    expect(find.text('输出记录'), findsNothing);
    expect(find.text('3'), findsOneWidget);
    pendingOutput.complete({'this_week': 1, 'total_count': 1});
    await tester.pumpAndSettle();
    expect(find.text('输出记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P11 AI 周报按钮必须先确认，取消不触发 AI 请求', (tester) async {
    tester.view.physicalSize = const Size(900, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: WeeklyReviewScreen(
        embedded: true,
        reviewLoader: () async => _week(4),
        outputStatsLoader: () async => {},
        dailyTrendLoader: () async => <Map<String, dynamic>>[],
      )),
    ));
    await tester.pumpAndSettle();
    final generate = find.text('生成 AI 周报 →');
    await tester.ensureVisible(generate);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.text('确认生成 AI 周报？'), findsOneWidget);
    expect(find.text('确认生成'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('确认生成 AI 周报？'), findsNothing);
    expect(find.text('正在生成 AI 周报…'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
