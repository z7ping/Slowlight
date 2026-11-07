import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
