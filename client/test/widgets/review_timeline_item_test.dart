import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/widgets/review/review_timeline_item.dart';

import '../support/fx_test_host.dart';

void main() {
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
