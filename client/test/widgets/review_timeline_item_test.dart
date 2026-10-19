import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/widgets/review/review_timeline_item.dart';

import '../support/fx_test_host.dart';

void main() {
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
