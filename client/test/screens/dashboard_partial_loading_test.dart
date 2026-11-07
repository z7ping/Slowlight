import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/dashboard/dashboard_body.dart';

import '../support/fx_test_host.dart';

void main() {
  Widget host({
    required Future<Map<String, dynamic>> Function() dimensions,
    required Future<Map<String, dynamic>> Function() review,
  }) => buildFxTestHost(
    home: Scaffold(
      body: DashboardBody(
        tasks: const [],
        habits: const [],
        dimensionLoader: dimensions,
        reviewLoader: review,
        timelineLoader: () async => const [],
      ),
    ),
  );

  testWidgets('附加请求仍在加载时，已加载的任务习惯与新增入口不被遮蔽', (tester) async {
    final slowDimensions = Completer<Map<String, dynamic>>();
    final slowReview = Completer<Map<String, dynamic>>();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(
      dimensions: () => slowDimensions.future,
      review: () => slowReview.future,
    ));
    await tester.pump();
    expect(find.text('今日任务'), findsOneWidget);
    expect(find.text('习惯'), findsOneWidget);
    expect(find.text('正在读取今日提问…'), findsOneWidget);
    slowDimensions.complete({'dimensions': []});
    slowReview.complete({'questions': [], 'facts': {}});
    await tester.pumpAndSettle();
    await disposeFxTestHost(tester);
  });

  testWidgets('统计与提问分别失败，核心记录仍可见且能重新读取', (tester) async {
    var attempt = 0;
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(
      dimensions: () async => throw Exception('统计接口不可用'),
      review: () async {
        if (attempt++ == 0) throw Exception('回顾接口不可用');
        return {'questions': [], 'facts': {}};
      },
    ));
    await tester.pumpAndSettle();
    expect(find.text('今日任务'), findsOneWidget);
    expect(find.text('习惯'), findsOneWidget);
    expect(find.text('今日提问暂时无法读取'), findsOneWidget);
    await tester.tap(find.text('重试').first);
    await tester.pumpAndSettle();
    expect(find.text('今日提问暂时无法读取'), findsNothing);
    expect(find.text('今日提问'), findsNothing);
    await disposeFxTestHost(tester);
  });

  testWidgets('P02 今天刷新失败保留已确认事实、四维足迹与提问', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var dimensionReads = 0;
    var reviewReads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: DashboardBody(
          tasks: const [],
          habits: const [],
          timelineLoader: () async => const [],
          dimensionLoader: () async {
            if (++dimensionReads > 1) {
              throw StateError('维度刷新不可用');
            }
            return {
              'dimensions': [
                {
                  'key': 'body',
                  'name': '身体',
                  'color': '#3B82F6',
                  'active_days': [
                    DateTime.now().toIso8601String().substring(0, 10),
                  ],
                },
              ],
            };
          },
          reviewLoader: () async {
            if (++reviewReads > 1) {
              throw StateError('今日回顾刷新不可用');
            }
            return {
              'questions': [
                {
                  'id': 'question-1',
                  'content': '今天想记录什么',
                  'type': 'reflection',
                },
              ],
              'facts': {
                'task_completed': 3,
                'habit_checked': 1,
                'focus_minutes': 25,
              },
            };
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('身体'), findsOneWidget);
    expect(find.text('今天想记录什么'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.widget<FxRefresh>(find.byType(FxRefresh)).onRefresh();
    await tester.pumpAndSettle();
    expect(dimensionReads, 2);
    expect(reviewReads, 2);
    expect(find.text('四维统计刷新未确认，以下为上次数据'), findsOneWidget);
    expect(find.text('今日事实刷新未确认，显示上次数据'), findsOneWidget);
    expect(find.text('今日提问刷新未确认，以下为上次提问'), findsOneWidget);
    expect(find.text('身体'), findsOneWidget);
    expect(find.text('今天想记录什么'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('点击去回应 →'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('只有统计失败时，问题仍正常呈现', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(
      dimensions: () async => throw Exception('统计超时'),
      review: () async => {'questions': [], 'facts': {}},
    ));
    await tester.pumpAndSettle();
    expect(find.text('今日任务'), findsOneWidget);
    expect(find.text('今日提问'), findsNothing);
    await disposeFxTestHost(tester);
  });
}
