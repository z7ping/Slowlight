import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final variant in FxIconButtonVariant.values) {
      testWidgets('${platform.name} $variant 图标按钮焦点不改变尺寸且可键盘触发', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        var count = 0;
        await tester.pumpWidget(buildFxTestHost(
          home: Scaffold(body: Center(child: FxIconButton(
            icon: Icons.refresh, variant: variant,
            onPressed: () { count++; },
          ))),
        ));
        final button = find.byType(FxIconButton);
        final size = tester.getSize(button);
        expect(size, Size.square(platform == TargetPlatform.android ? 44 : 30));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final focusColor = Theme.of(tester.element(button)).colorScheme.primary;
        final decorations = tester.widgetList<DecoratedBox>(find.descendant(
          of: button, matching: find.byType(DecoratedBox),
        ));
        expect(decorations.any((box) {
          final decoration = box.decoration;
          return decoration is BoxDecoration && decoration.border is Border &&
              (decoration.border! as Border).top.color == focusColor;
        }), isTrue, reason: '键盘焦点必须有可见描边');
        expect(tester.getSize(button), size);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(count, 1);
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }
  }

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
    // Let the async action's finally block rebuild the enabled Shad button.
    await tester.pumpAndSettle();
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
    // Let the async action's finally block rebuild the enabled Shad button.
    await tester.pumpAndSettle();
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
