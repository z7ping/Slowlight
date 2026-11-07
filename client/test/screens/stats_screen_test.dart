import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/screens/stats_screen.dart';
import 'package:slowlight/screens/stats/stats_snapshot.dart';

import '../support/fx_test_host.dart';

StatsSnapshot _snapshot({Set<String> unavailable = const {}}) {
  final now = DateTime.now();
  final day = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  return StatsSnapshot(
    taskStats: const {'completed': 90, 'total': 100},
    dailyTrend: [{'date': day, 'task_completed': 99, 'habit_checked': 2}],
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
