import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('任务骨架保持真实列表结构，并延迟 150ms 显示', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: const Scaffold(
        body: FxSkeletonPage(kind: FxSkeletonPageKind.tasks),
      ),
    ));

    expect(find.byKey(const ValueKey('skeleton.tasks')), findsOneWidget);
    expect(find.byType(FxSkeleton), findsWidgets);
    expect(find.byType(FxSkeletonList), findsOneWidget);
    final group = find.byType(FxSkeletonGroup);
    expect(
      tester.widget<Opacity>(
        find.descendant(of: group, matching: find.byType(Opacity)).first,
      ).opacity,
      0,
    );

    await tester.pump(const Duration(milliseconds: 160));
    expect(
      tester.widget<Opacity>(
        find.descendant(of: group, matching: find.byType(Opacity)).first,
      ).opacity,
      greaterThan(0),
    );
    await disposeFxTestHost(tester);
  });

  testWidgets('系统减少动画时骨架静止可见，卸载后无遗留定时器', (tester) async {
    await tester.pumpWidget(buildFxTestHost(
      home: const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: FxSkeletonPage(kind: FxSkeletonPageKind.review),
        ),
      ),
    ));

    await tester.pump(const Duration(milliseconds: 180));
    expect(
      tester.widget<Opacity>(
        find.descendant(
          of: find.byType(FxSkeletonGroup),
          matching: find.byType(Opacity),
        ).first,
      ).opacity,
      1,
    );
    await disposeFxTestHost(tester);
  });
}
