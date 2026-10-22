import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
