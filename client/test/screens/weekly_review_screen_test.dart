import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/reflection_entry.dart';
import 'package:slowlight/models/today_timeline_item.dart';
import 'package:slowlight/repositories/reflection_repository.dart';
import 'package:slowlight/screens/weekly_review_screen.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/review/review_timeline_item.dart';

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

class _WeekResponseRepo extends ReflectionRepository {
  final confirmed = <String, ReflectionEntry?>{};
  final pending = <String, Completer<ReflectionEntry?>>{};

  @override
  Future<ReflectionEntry?> findPeriodResponse(
    String questionId, {
    String? legacyWeekStart,
    String? legacyWeekEnd,
  }) async {
    final deferred = pending[questionId];
    if (deferred != null) return deferred.future;
    return confirmed[questionId];
  }
}

Map<String, dynamic> _datedWeek(int count, String start, String end) => {
  ..._week(count),
  'week_start': start,
  'week_end': end,
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
  testWidgets('P11 切换周后旧回应立即隐藏，核对新周后才能保存', (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const previous = 'review-week:2026-11-02:2026-11-08';
    const next = 'review-week:2026-11-09:2026-11-15';
    final repo = _WeekResponseRepo();
    repo.confirmed[previous] = ReflectionEntry(
      id: 75,
      content: '上周已确认的回应',
      entryType: 'reflection',
      questionId: previous,
      createdAt: DateTime(2026, 11, 8),
    );
    final nextRead = Completer<ReflectionEntry?>();
    repo.pending[next] = nextRead;
    var revision = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: WeeklyReviewScreen(
        embedded: true,
        reflectionRepository: repo,
        reviewLoader: () async => ++revision == 1
            ? _datedWeek(3, '2026-11-02', '2026-11-08')
            : _datedWeek(4, '2026-11-09', '2026-11-15'),
        outputStatsLoader: () async => {},
        dailyTrendLoader: () async => [],
        periodTimelineLoader: () async => const ReviewPeriodTimeline(
          observationCount: 0, items: [],
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('上周已确认的回应'), findsOneWidget);

    await tester.widget<FxRefresh>(find.byType(FxRefresh)).onRefresh();
    await tester.pump();
    expect(find.text('上周已确认的回应'), findsNothing);
    expect(find.widgetWithText(FxButton, '保存回应'), findsNothing);

    nextRead.complete(null);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FxButton, '保存回应'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P11 刷新未完成时不能用旧周事实保存回应', (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pendingReview = Completer<Map<String, dynamic>>();
    var revision = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: WeeklyReviewScreen(
        embedded: true,
        reflectionRepository: _WeekResponseRepo(),
        reviewLoader: () => ++revision == 1
            ? Future.value(_datedWeek(3, '2026-11-02', '2026-11-08'))
            : pendingReview.future,
        outputStatsLoader: () async => {},
        dailyTrendLoader: () async => [],
        periodTimelineLoader: () async => const ReviewPeriodTimeline(
          observationCount: 0, items: [],
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FxButton, '保存回应'), findsOneWidget);

    unawaited(tester.widget<FxRefresh>(find.byType(FxRefresh)).onRefresh());
    await tester.pump();
    expect(tester.widget<FxButton>(
      find.widgetWithText(FxButton, '保存回应'),
    ).onPressed, isNull);

    pendingReview.complete(_datedWeek(4, '2026-11-09', '2026-11-15'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FxButton, '保存回应'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P11 上周为零也是有效比较，观察事实不算空周', (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: WeeklyReviewScreen(
        embedded: true,
        reflectionRepository: _WeekResponseRepo(),
        reviewLoader: () async => {
          ..._datedWeek(0, '2026-11-02', '2026-11-08'),
          'habit_checked': 0,
          'focus_minutes': 0,
          'habit_last_week': 0,
          'task_last_week': 0,
          'focus_last_week': 0,
        },
        outputStatsLoader: () async => {},
        dailyTrendLoader: () async => [],
        periodTimelineLoader: () async => const ReviewPeriodTimeline(
          observationCount: 1,
          items: [],
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('这一周还没有行为记录'), findsNothing);
    expect(find.text('本周有 1 条观察，事件明细尚未载入。'), findsOneWidget);
    expect(find.text('数据积累中，下周会有可对比记录。'), findsNothing);
    expect(find.text('和上周比'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P11 滚动 7 日趋势不将上周计入本周', (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: WeeklyReviewScreen(
        embedded: true,
        reflectionRepository: _WeekResponseRepo(),
        reviewLoader: () async => _datedWeek(2, '2026-11-02', '2026-11-08'),
        outputStatsLoader: () async => {},
        dailyTrendLoader: () async => [
          {'date': '2026-10-30', 'task_completed': 9, 'habit_checked': 0},
          {'date': '2026-11-02', 'task_completed': 2, 'habit_checked': 0},
        ],
        periodTimelineLoader: () async => const ReviewPeriodTimeline(
          observationCount: 0, items: [],
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('每日记录'), findsOneWidget);
    expect(find.text('一'), findsOneWidget);
    expect(find.text('五'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P11 Android 相关工具复用正式回顾导航回调', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.reset();
    });
    var stats = 0;
    var time = 0;
    var thirtyDays = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: WeeklyReviewScreen(
        embedded: true,
        reviewLoader: () async => _week(2),
        outputStatsLoader: () async => {},
        dailyTrendLoader: () async => [],
        periodTimelineLoader: () async => const ReviewPeriodTimeline(
          observationCount: 0, items: [],
        ),
        onOpenStats: () => stats++,
        onOpenTimeDistribution: () => time++,
        onOpenThirtyDays: () => thirtyDays++,
      )),
    ));
    await tester.pumpAndSettle();
    for (final label in ['查看记录统计', '查看时间分配', '查看近 30 天']) {
      expect(find.widgetWithText(FxButton, label), findsOneWidget);
      tester.widget<FxButton>(find.widgetWithText(FxButton, label))
          .onPressed?.call();
    }
    expect(stats, 1);
    expect(time, 1);
    expect(thirtyDays, 1);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P11 本周轨迹失败可独立重试，不丢统计快照', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var attempts = 0;
    var reviews = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: WeeklyReviewScreen(
        embedded: true,
        reflectionRepository: _WeekResponseRepo(),
        reviewLoader: () async {
          reviews++;
          return _datedWeek(7, '2026-11-02', '2026-11-08');
        },
        outputStatsLoader: () async => {},
        dailyTrendLoader: () async => [],
        periodTimelineLoader: () async {
          if (++attempts == 1) throw StateError('temporary');
          return const ReviewPeriodTimeline(observationCount: 1, items: []);
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(reviews, 1);
    expect(find.textContaining('本周轨迹读取未确认'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);

    tester.widget<FxButton>(find.widgetWithText(FxButton, '重试轨迹'))
        .onPressed?.call();
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(reviews, 1);
    expect(find.textContaining('本周轨迹读取未确认'), findsNothing);
    expect(find.text('本周有 1 条观察，事件明细尚未载入。'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 本周筛选原生轨迹，保留记录类型和真实日期', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.reset();
    });
    final now = DateTime.now();
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(body: WeeklyReviewScreen(
        embedded: true,
        reviewLoader: () async => _week(2),
        outputStatsLoader: () async => {},
        dailyTrendLoader: () async => [],
        periodTimelineLoader: () async => ReviewPeriodTimeline(
          observationCount: 1,
          items: [
            TodayTimelineItem(
              id: 'task:71', kind: 'task_completed',
              title: '整理工作笔记', durationMinutes: 0, occurredAt: now,
            ),
            TodayTimelineItem(
              id: 'reflection:72', kind: 'observation',
              title: '今天记录了一点变化', durationMinutes: 0, occurredAt: now,
            ),
          ],
        ),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review.week.metric.task_completed')),
        findsOneWidget);
    await tester.tap(find.byKey(
        const ValueKey('review.week.metric.task_completed')));
    await tester.pumpAndSettle();
    final visible = tester.widgetList<ReviewTimelineItem>(
        find.byType(ReviewTimelineItem));
    expect(visible.length, 1);
    expect(visible.single.kind, 'task_completed');
    expect(visible.single.compact, isTrue);

    await tester.tap(find.byKey(
        const ValueKey('review.week.metric.task_completed')));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewTimelineItem), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
