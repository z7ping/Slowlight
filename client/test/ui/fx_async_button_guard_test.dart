import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('FxButton 异步提交执行中忽略连续点击，完成后可再次点击', (tester) async {
    final pending = Completer<void>();
    var count = 0;

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Center(
          child: FxButton(
            label: '保存',
            onPressed: () {
              count++;
              return pending.future;
            },
          ),
        ),
      ),
    ));

    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(count, 1);

    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(count, 1);

    pending.complete();
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(count, 2);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('FxIconButton 异步操作执行中忽略连续点击', (tester) async {
    final pending = Completer<void>();
    var count = 0;

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Center(
          child: FxIconButton(
            icon: Icons.refresh,
            onPressed: () {
              count++;
              return pending.future;
            },
          ),
        ),
      ),
    ));

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(count, 1);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(count, 1);

    pending.complete();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(count, 2);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('同步导航动作不额外施加固定毫秒级防抖', (tester) async {
    var count = 0;

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Center(
          child: FxButton(label: '切换', onPressed: () { count++; }),
        ),
      ),
    ));

    await tester.tap(find.text('切换'));
    await tester.pump();
    await tester.tap(find.text('切换'));
    await tester.pump();
    expect(count, 2);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('异步操作完成前卸载按钮不会触发已销毁 State 更新', (tester) async {
    final pending = Completer<void>();

    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: FxButton(label: '运行', onPressed: () => pending.future),
      ),
    ));
    await tester.tap(find.text('运行'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    pending.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
