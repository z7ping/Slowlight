import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/widgets/task_swipe_row.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/ui/theme_manager.dart';

import '../support/fx_test_host.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('滑动前景在${dark ? '深色' : '浅色'}主题保持完整不透明背景',
        (tester) async {
      var open = false;
      await tester.pumpWidget(buildFxTestHost(
        theme: dark ? ThemeManager.darkTheme : ThemeManager.lightTheme,
        shadTheme: dark ? ThemeManager.shadDark : ThemeManager.shadLight,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: StatefulBuilder(builder: (context, update) {
                return TaskSwipeRow(
                  open: open,
                  onOpenChanged: (next) => update(() => open = next),
                  onComplete: () async {},
                  onPostpone: () async {},
                  onMore: () {},
                  child: const SizedBox(
                    height: 64,
                    child: Center(child: Text('可滑动任务')),
                  ),
                );
              }),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final surface = find.byKey(const ValueKey('taskSwipe.foreground'));
      expect(surface, findsOneWidget);
      expect(
        tester.widget<ColoredBox>(surface).color,
        fxSurface(tester.element(surface)),
      );
      final initialLeft = tester.getTopLeft(surface).dx;
      await tester.drag(find.text('可滑动任务'), const Offset(-105, 0));
      await tester.pumpAndSettle();
      expect(open, isTrue);
      expect(tester.getTopLeft(surface).dx, lessThan(initialLeft - 60));
      expect(tester.widget<ColoredBox>(surface).color,
          fxSurface(tester.element(surface)));
      expect(tester.takeException(), isNull);
      await disposeFxTestHost(tester);
    });
  }

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
                onComplete: () async { completeCount++; },
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
                onPostpone: () async { postponeCount++; },
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
                onComplete: () async { completeCount++; },
                onPostpone: () async { postponeCount++; },
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
