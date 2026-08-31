import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  Widget buildHost() {
    return buildFxTestHost(
      home: Builder(
        builder: (context) => Scaffold(
          body: FxButton(
            label: '打开弹窗',
            onPressed: () => FxDialog.confirm(
              context: context,
              title: '删除任务',
              content: '确定删除吗？',
              confirmText: '删除',
              destructive: true,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('FxDialog 使用统一遮罩并允许点击外部取消', (tester) async {
    await tester.pumpWidget(buildHost());
    final barrierBaseline = find.byType(ModalBarrier).evaluate().length;

    await tester.tap(find.text('打开弹窗'));
    await tester.pumpAndSettle();

    final barriers = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier));
    expect(find.byType(ModalBarrier), findsNWidgets(barrierBaseline + 1));
    expect(
      barriers.any((barrier) => barrier.color == FxDialog.barrierColor),
      isTrue,
    );

    expect(tester.widget<Text>(find.text('取消')).style, isNull);
    expect(tester.widget<Text>(find.text('删除')).style, isNull);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('删除任务'), findsNothing);
    expect(find.byType(ModalBarrier), findsNWidgets(barrierBaseline));
    await disposeFxTestHost(tester);
  });
}
