import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/stats_screen.dart';
import 'package:slowlight/screens/stats/stats_snapshot.dart';

import '../support/fx_test_host.dart';

StatsSnapshot _snapshot({
  Set<String> unavailable = const {},
  bool fullTrend = false,
  bool observationCounts = false,
}) {
  final now = DateTime.now();
  final day = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  return StatsSnapshot(
    taskStats: const {'completed': 90, 'total': 100},
    dailyTrend: fullTrend
        ? List.generate(7, (i) {
            final date = DateTime(now.year, now.month, now.day - 6 + i);
            final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            return {
              'date': key,
              'task_completed': i == 6 ? 99 : 1,
              'habit_checked': i == 6 ? 2 : 1,
              if (observationCounts) 'reflection_count': i == 6 ? 2 : 0,
            };
          })
        : [{'date': day, 'task_completed': 99, 'habit_checked': 2}],
    listStats: const [],
    tagStats: const [],
    habits: const [],
    sessionStats: {
      'total_work_seconds': 1500,
      'daily': [
        {'date': day, 'work_seconds': 1500, 'work_count': 1},
      ],
    },
    todaySessionStats: const {'total_work_seconds': 1500},
    reminderStats: const {},
    timeDistribution: const {},
    outputStats: const {},
    unavailableSources: unavailable,
  );
}

void main() {
  test('P10 专注趋势只能来自 WorkSession 时长，不能回退任务完成数', () {
    final snapshot = _snapshot();
    expect(snapshot.focusLast7, hasLength(7));
    expect(snapshot.focusLast7.last.minutes, 25);
    expect(snapshot.focusLast7.last.minutes, isNot(99));
  });

  testWidgets('P10 某来源未确认时不将周任务和专注伪装成 0',
      (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: StatsScreen(
          snapshotLoader: () async => _snapshot(
            unavailable: {'daily_trend', 'session_stats'},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('部分统计来源未读取，未确认的数据以「—」表示。'), findsOneWidget);
    expect(find.text('近 7 天专注记录暂不可用'), findsOneWidget);
    expect(find.text('99 分钟'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  test('P10 日期口径独立：近七个自然日、今天和缺失观察值', () {
    final snapshot = _snapshot(fullTrend: true);
    expect(snapshot.countInDays('task_completed', 7), 105);
    expect(snapshot.countInDays('task_completed', 1), 99);
    expect(snapshot.countInDays('habit_checked', 7), 8);
    expect(snapshot.focusMinutesInDays(7), 25);
    expect(snapshot.focusMinutesInDays(1), 25);
    // Old Cloud API snapshots do not include the new observation field.
    expect(snapshot.observationCountInDays(7), isNull);
    expect(_snapshot(fullTrend: true, observationCounts: true)
        .observationCountInDays(7), 2);
    expect(
      _snapshot(unavailable: {'today_session_stats'})
          .focusMinutesInDays(1),
      isNull,
    );
    expect(
      _snapshot(unavailable: {'daily_trend'})
          .countInDays('task_completed', 1),
      isNull,
    );
  });

  testWidgets('P10 Android 周期切换与全部 KPI 使用现有导航回调',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final destinations = <StatsDestination>[];
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: StatsScreen(
          snapshotLoader: () async => _snapshot(fullTrend: true),
          onNavigate: destinations.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('记录概况'), findsOneWidget);
    expect(find.text('105'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    await tester.ensureVisible(
      find.text('观察数量未纳入趋势（当前来源未提供每日观察事实）'),
    );
    expect(find.text('观察数量未纳入趋势（当前来源未提供每日观察事实）'),
        findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('stats.kpi.tasks')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stats.kpi.tasks')));
    expect(destinations, [StatsDestination.tasks]);
    await tester.tap(find.text('今天').first);
    await tester.pumpAndSettle();
    expect(find.text('99'), findsWidgets);
    expect(find.text('今日专注'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stats.kpi.habits')));
    expect(destinations.last, StatsDestination.habits);
    await tester.tap(find.byKey(const ValueKey('stats.kpi.focus')));
    expect(destinations.last, StatsDestination.focus);
    await tester.tap(find.byKey(const ValueKey('stats.kpi.review')));
    expect(destinations.last, StatsDestination.review);

    await tester.ensureVisible(find.text('查看详细时间分配'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看详细时间分配'));
    expect(destinations.last, StatsDestination.timeDistribution);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('P10 320dp 大字保持统计操作与事实可滚动', (tester) async {
    tester.view.physicalSize = const Size(320, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 680),
          textScaler: TextScaler.linear(2),
        ),
        child: Scaffold(
          body: StatsScreen(
            snapshotLoader: () async => _snapshot(fullTrend: true),
            onNavigate: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stats.kpi.tasks')), findsOneWidget);
    await tester.ensureVisible(find.text('查看详细时间分配'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  group('StatsScreen 响应式稳定性', () {
    for (final size in [
      const Size(400, 800),
      const Size(1200, 800),
    ]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()} 不产生布局异常',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          buildFxTestHost(home: const Scaffold(body: StatsScreen())),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }
  });
}
