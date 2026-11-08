import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/today_timeline_item.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/review/task_30day_tab.dart';

import '../support/fx_test_host.dart';

Map<String, dynamic> _month({int completed = 0, int created = 0}) => {
  'summary': {
    'completed_count': completed,
    'created_count': created,
    'total_days': 30,
  },
  'distribution': <String, dynamic>{},
  'completed_tasks': <Map<String, dynamic>>[],
};

void main() {
  testWidgets('P12 只有习惯记录不能冒充近30天任务活动', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskMonthTab(
        tasksReviewLoader: () async => _month(),
        dailyTrendLoader: () async => [
          {'date': '2026-11-06', 'habit_checked': 5, 'task_completed': 0},
        ],
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('习惯记录'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('近 30 天还没有任务记录'), findsOneWidget);
    expect(find.text('每日任务完成趋势'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P12 主任务回顾刷新失败保留确认事实且不重读其他周期趋势',
      (tester) async {
    var primaryReads = 0;
    var trendReads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskMonthTab(
        tasksReviewLoader: () async {
          if (++primaryReads == 1) return _month(completed: 4, created: 2);
          throw StateError('任务回顾暂不可用');
        },
        dailyTrendLoader: () async {
          trendReads++;
          return [
            {'date': '2026-11-06', 'task_completed': 2, 'habit_checked': 1},
          ];
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);
    expect(trendReads, 1);

    await tester.widget<FxRefresh>(find.byType(FxRefresh)).onRefresh();
    await tester.pumpAndSettle();
    expect(primaryReads, 2);
    expect(trendReads, 1);
    expect(find.text('4'), findsOneWidget);
    expect(find.textContaining('近 30 天数据刷新未确认'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
  testWidgets('P12 历史 25 条完成任务全部可达，显示真实日期', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tasks = List.generate(25, (index) => <String, dynamic>{
      'id': index + 1,
      'title': '任务#${index + 1}',
      'completed_date': index == 0 ? '2026-11-06' : null,
      'completed_at': '15:20',
      'list_name': '工作',
    });
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskMonthTab(
        tasksReviewLoader: () async => {
          ..._month(completed: 25),
          'completed_tasks': tasks,
        },
        dailyTrendLoader: () async => [],
        periodTimelineLoader: () async => const ReviewPeriodTimeline(
          observationCount: 0, items: [],
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('任务#1'), findsOneWidget);
    expect(find.text('任务#20'), findsOneWidget);
    expect(find.text('任务#21'), findsNothing);
    expect(find.text('11/6 · 15:20'), findsOneWidget);
    expect(find.text('日期未载入 · 15:20'), findsNWidgets(19));
    expect(find.text('已显示 20/25 条'), findsOneWidget);

    tester.widget<FxButton>(find.widgetWithText(FxButton, '查看更多任务'))
        .onPressed?.call();
    await tester.pumpAndSettle();
    expect(find.text('任务#25'), findsOneWidget);
    expect(find.text('25 条'), findsOneWidget);
    expect(find.widgetWithText(FxButton, '查看更多任务'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P12 轨迹读取失败可以局部重试，不重新加载主任务事实', (tester) async {
    tester.view.physicalSize = const Size(950, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var primaryReads = 0;
    var timelineReads = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskMonthTab(
        tasksReviewLoader: () async {
          primaryReads++;
          return _month(completed: 4, created: 1);
        },
        dailyTrendLoader: () async => [],
        periodTimelineLoader: () async {
          if (++timelineReads == 1) throw StateError('read unavailable');
          return const ReviewPeriodTimeline(observationCount: 2, items: []);
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('近 30 天轨迹读取未确认'), findsOneWidget);
    tester.widget<FxButton>(find.widgetWithText(FxButton, '重试轨迹'))
        .onPressed?.call();
    await tester.pumpAndSettle();
    expect(primaryReads, 1);
    expect(timelineReads, 2);
    expect(find.text('近 30 天有 2 条观察，事件明细尚未载入。'), findsOneWidget);
    expect(find.textContaining('近 30 天轨迹读取未确认'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P12 Android 近 30 天使用现有回顾入口返回本周', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.reset();
    });
    var navigateCount = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: TaskMonthTab(
        tasksReviewLoader: () async => _month(),
        dailyTrendLoader: () async => [],
        periodTimelineLoader: () async => const ReviewPeriodTimeline(
          observationCount: 0, items: [],
        ),
        onOpenWeekly: () => navigateCount++,
      )),
    ));
    await tester.pumpAndSettle();
    final back = find.widgetWithText(FxButton, '查看本周回顾');
    expect(back, findsOneWidget);
    tester.widget<FxButton>(back).onPressed?.call();
    expect(navigateCount, 1);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
