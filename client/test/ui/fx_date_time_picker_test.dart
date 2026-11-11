import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('FxTimePicker 中文界面使用时分秒标签', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        home: Builder(
          builder: (context) => Scaffold(
            body: FxButton(
              label: '选择时间',
              onPressed: () => showFxTimePicker(
                context: context,
                initialTime: const TimeOfDay(hour: 9, minute: 30),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('选择时间'));
    await tester.pumpAndSettle();

    expect(find.text('时'), findsOneWidget);
    expect(find.text('分'), findsOneWidget);
    expect(find.text('秒'), findsOneWidget);
    expect(find.text('Hours'), findsNothing);
    expect(find.text('Minutes'), findsNothing);
    expect(find.text('Seconds'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 补记日期仅允许范围内日期，且使用统一 Sheet', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final today = DateUtils.dateOnly(DateTime.now());
    final last = today.subtract(const Duration(days: 1));
    final first = today.subtract(const Duration(days: 2));
    DateTime? selected;
    await tester.pumpWidget(buildFxTestHost(
      home: Builder(
        builder: (context) => Scaffold(
          body: FxButton(
            label: '打开补记日期',
            onPressed: () async {
              selected = await showFxDatePicker(
                context: context,
                initialDate: last,
                firstDate: first,
                lastDate: last,
                title: '选择补卡日期',
              );
            },
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开补记日期'));
    await tester.pumpAndSettle();
    expect(find.text('选择补卡日期'), findsOneWidget);
    expect(find.textContaining('可选日期：'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.text('今天'), findsNothing);

    String key(DateTime date) =>
        'fx.date.day.${date.year}-${date.month}-${date.day}';
    // 不可选日期没有交互，也不会修改初始选中日。
    if (first.day > 1) {
      final before = first.subtract(const Duration(days: 1));
      await tester.tap(find.byKey(ValueKey(key(before))));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(ValueKey(key(first))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(selected, first);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
