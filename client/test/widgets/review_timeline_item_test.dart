import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:slowlight/widgets/review/review_timeline_item.dart';
import 'package:slowlight/widgets/timeline_type_label.dart';
import 'package:slowlight/ui/app_theme.dart';

import '../support/fx_test_host.dart';

void main() {
  test('今天与回顾共用语义类别颜色及类型映射', () {
    expect(TimelineTypeLabel.baseColorFor('task_completed'), AppTheme.chartGreen);
    expect(TimelineTypeLabel.baseColorFor('habit_checked'), AppTheme.chartYellow);
    expect(TimelineTypeLabel.baseColorFor('observation'), AppTheme.chartPurple);
    expect(TimelineTypeLabel.baseColorFor('session_ended'), AppTheme.info);
    expect(TimelineTypeLabel.labelFor('habit_checked'), '习惯');
    expect(TimelineTypeLabel.labelFor('task_completed'), '任务');
  });

  testWidgets('回顾无附加详情时不出现无效展开与重复时间', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: const Scaffold(
        body: ReviewTimelineItem(
          color: AppTheme.chartYellow,
          kind: 'habit_checked',
          compact: true,
          time: '10:03',
          title: '记录了早起',
        ),
      ),
    ));
    final marker = find.byType(TimelineTypeLabel);
    expect(marker, findsOneWidget);
    expect(tester.widget<TimelineTypeLabel>(marker).baseColor, AppTheme.chartYellow);
    expect(find.text('习惯'), findsOneWidget);
    expect(find.byIcon(LucideIcons.chevronDown), findsNothing);
    expect(find.text('10:03'), findsOneWidget);
    await tester.tap(find.text('记录了早起'));
    await tester.pump();
    expect(find.text('10:03'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('回顾有实际备注才提供展开，展开后不重复时间', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: const Scaffold(
        body: ReviewTimelineItem(
          color: AppTheme.chartYellow,
          kind: 'habit_checked',
          compact: true,
          time: '09:11',
          title: '记录了早起',
          note: '今天状态很好',
        ),
      ),
    ));
    expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
    expect(find.text('今天状态很好'), findsNothing);
    await tester.tap(find.text('记录了早起'));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.chevronUp), findsOneWidget);
    expect(find.text('今天状态很好'), findsOneWidget);
    expect(find.text('09:11'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  test('事实时间线先展示有确定时刻的记录，按时间正序', () {
    const undated = ReviewTimelineItem(
      color: Colors.grey, time: '今天', title: '汇总',
    );
    const afternoon = ReviewTimelineItem(
      color: Colors.grey, time: '15:20', title: '下午',
    );
    const morning = ReviewTimelineItem(
      color: Colors.grey, time: '09:05', title: '早晨',
    );
    final records = [undated, afternoon, morning]
      ..sort(compareReviewTimelineItems);

    expect(records.map((entry) => entry.title).toList(), [
      '早晨', '下午', '汇总',
    ]);
  });


  testWidgets('ReviewTimelineItem 在 360dp + 200% 字体缩放下不溢出',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildFxTestHost(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: ReviewTimelineItem(
              color: Colors.green,
              time: '今天 14:30',
              title: '完成一个比较长的回顾事实标题，用于验证系统大字体下可以自然换行',
              note: '这是一段较长的补充说明，应该随字体缩放自然增加高度，而不是发生布局溢出。',
            ),
          ),
        ),
      ),
    );

    expect(find.text('今天 14:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
