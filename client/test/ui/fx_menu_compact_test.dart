import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('Android FxMenu 统一右侧选中勾、紧凑行与单选自动关闭',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    int? selected;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: FxMenu<int>(
            initialValue: 0,
            constraints: const BoxConstraints(minWidth: 190, maxWidth: 190),
            onSelected: (value) => selected = value,
            itemBuilder: (_) => const [
              FxMenuItem<int>(
                value: 0,
                child: Row(children: [
                  Expanded(child: Text('全部')),
                  Icon(LucideIcons.check, size: 17),
                ]),
              ),
              FxMenuItem<int>(value: 1, child: Text('今日未记录')),
              FxMenuItem<int>(value: 2, child: Text('今日有记录')),
            ],
            child: const SizedBox(
              width: 44, height: 44, child: Icon(LucideIcons.listFilter),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byIcon(LucideIcons.listFilter));
    await tester.pumpAndSettle();

    final first = find.text('全部');
    final second = find.text('今日未记录');
    final third = find.text('今日有记录');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(third, findsOneWidget);
    // Each of the two consecutive gaps represents a >=44dp touch row.
    expect(tester.getTopLeft(third).dy - tester.getTopLeft(first).dy,
        greaterThanOrEqualTo(88));
    expect(tester.getTopLeft(first).dx,
        lessThan(tester.getTopLeft(find.byIcon(LucideIcons.check)).dx));

    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.text('今日未记录'), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
