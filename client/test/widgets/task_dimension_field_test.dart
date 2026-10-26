import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/widgets/task_dimension_field.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('四维归属使用同一套 Fx 选择控件，并允许取消归类', (tester) async {
    String? selected;
    await tester.pumpWidget(
      buildFxTestHost(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TaskDimensionField(
              selectedKey: selected,
              onChanged: (key) => setState(() => selected = key),
            ),
          ),
        ),
      ),
    );

    expect(find.text('未归类'), findsOneWidget);
    expect(find.text('💪 身体'), findsOneWidget);
    expect(find.text('🧠 认知'), findsOneWidget);
    expect(find.text('🎯 产出'), findsOneWidget);
    expect(find.text('❤️ 关系'), findsOneWidget);

    await tester.tap(find.text('🧠 认知'));
    await tester.pump();
    expect(selected, 'cognition');

    await tester.tap(find.text('未归类'));
    await tester.pump();
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 360dp 大字体四维选项自动折行', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildFxTestHost(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 740),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: TaskDimensionField(
                selectedKey: 'body',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('💪 身体'), findsOneWidget);
    expect(find.text('❤️ 关系'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
