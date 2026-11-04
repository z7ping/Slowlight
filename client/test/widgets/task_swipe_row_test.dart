import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/widgets/task_swipe_row.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('任务右滑完成一次，不依赖隐藏操作区按钮', (tester) async {
    var open = false;
    var completeCount = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: StatefulBuilder(builder: (context, update) {
              return TaskSwipeRow(
                open: open,
                onOpenChanged: (next) => update(() => open = next),
                onComplete: () async => completeCount++,
                onPostpone: () async {},
                onMore: () {},
                child: const SizedBox(
                  height: 64,
                  child: Center(child: Text('拖动任务')),
                ),
              );
            }),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.text('拖动任务'), const Offset(118, 0));
    await tester.pumpAndSettle();
    expect(completeCount, 1);
    expect(open, isFalse);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('左滑露出顺延与更多，点击后自动收起', (tester) async {
    var open = false;
    var postponeCount = 0;
    var moreCount = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: StatefulBuilder(builder: (context, update) {
              return TaskSwipeRow(
                open: open,
                onOpenChanged: (next) => update(() => open = next),
                onComplete: () async {},
                onPostpone: () async => postponeCount++,
                onMore: () => moreCount++,
                child: const SizedBox(
                  height: 64,
                  child: Center(child: Text('拖动任务')),
                ),
              );
            }),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.text('拖动任务'), const Offset(-110, 0));
    await tester.pumpAndSettle();
    expect(open, isTrue);
    await tester.tap(find.text('顺延'));
    await tester.pumpAndSettle();
    expect(postponeCount, 1);
    expect(open, isFalse);

    await tester.drag(find.text('拖动任务'), const Offset(-110, 0));
    await tester.pumpAndSettle();
    expect(open, isTrue);
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(moreCount, 1);
    expect(open, isFalse);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('短距离滑动回弹，不误完成或顺延', (tester) async {
    var open = false;
    var completeCount = 0;
    var postponeCount = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: StatefulBuilder(builder: (context, update) {
              return TaskSwipeRow(
                open: open,
                onOpenChanged: (next) => update(() => open = next),
                onComplete: () async => completeCount++,
                onPostpone: () async => postponeCount++,
                onMore: () {},
                child: const SizedBox(
                  height: 64,
                  child: Center(child: Text('拖动任务')),
                ),
              );
            }),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.text('拖动任务'), const Offset(28, 0));
    await tester.pumpAndSettle();
    expect(completeCount, 0);
    expect(postponeCount, 0);
    expect(open, isFalse);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
