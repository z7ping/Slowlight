import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/today_timeline_item.dart';
import 'package:slowlight/widgets/dashboard/dashboard_body.dart';

import '../support/fx_test_host.dart';

void main() {
  final now = DateTime.now();
  final items = [
    TodayTimelineItem(
      id: 'reflection:5', kind: 'observation',
      title: '今天值得留意的一件小事',
      durationMinutes: 0, occurredAt: now,
    ),
    TodayTimelineItem(
      id: 'event:2', kind: 'session_ended',
      title: '', durationMinutes: 25,
      occurredAt: now.subtract(const Duration(minutes: 20)),
    ),
  ];

  Widget host({
    required double width,
    Future<List<TodayTimelineItem>> Function()? timeline,
    VoidCallback? onReview,
  }) => buildFxTestHost(
    home: Scaffold(body: MediaQuery(
      data: MediaQueryData(size: Size(width, 800)),
      child: DashboardBody(
        tasks: const [],
        habits: const [],
        reviewLoader: () async => {
          'questions': [],
          'facts': {
            'task_completed': 1,
            'habit_checked': 1,
            'focus_minutes': 25,
          },
        },
        dimensionLoader: () async => {
          'dimensions': [
            {
              'key': 'body', 'name': '身体', 'color': '#3B82F6',
              'active_days': [DateTime.now().toIso8601String().substring(0, 10)],
            },
          ],
        },
        timelineLoader: timeline ?? () async => items,
        onViewReview: onReview,
      ),
    )),
  );

  for (final width in [390.0, 1200.0]) {
    testWidgets('${width.toInt()} 今日轨迹与四维足迹共存，不阻断任务习惯', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(width: width));
      await tester.pumpAndSettle();
      expect(find.text('今日任务'), findsOneWidget);
      expect(find.text('习惯'), findsOneWidget);
      expect(find.text('今天值得留意的一件小事'), findsOneWidget);
      expect(find.text('专注 25 分钟'), findsOneWidget);
      expect(find.text('最近 7 天 · 四维足迹'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }

  testWidgets('时间轨迹请求卡住时，今日任务仍可使用', (tester) async {
    final pending = Completer<List<TodayTimelineItem>>();
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(width: 1200, timeline: () => pending.future));
    await tester.pump();
    expect(find.text('今日任务'), findsOneWidget);
    expect(find.text('正在读取今天的轨迹…'), findsOneWidget);
    pending.complete(items);
    await tester.pumpAndSettle();
    expect(find.text('专注 25 分钟'), findsOneWidget);
    await disposeFxTestHost(tester);
  });
}
