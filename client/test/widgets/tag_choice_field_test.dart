import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/observation_tag.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/tag_choice_field.dart';

import '../support/fx_test_host.dart';

void main() {
  const tags = [
    ObservationTag(id: 1, name: '学习', icon: '📚', color: '#1890ff'),
    ObservationTag(id: 2, name: '阅读', icon: '📖', color: '#52c41a'),
  ];

  testWidgets('标签选择统一使用 Fx 组件且可以清空', (tester) async {
    int? selected;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => TagChoiceField(
            tags: tags,
            selectedTagId: selected,
            onChanged: (id) => setState(() => selected = id),
          ),
        ),
      ),
    ));
    expect(find.text('标签（可选）'), findsOneWidget);
    expect(find.text('#学习'), findsOneWidget);
    expect(find.text('#阅读'), findsOneWidget);
    await tester.tap(find.text('#学习'));
    await tester.pump();
    expect(selected, 1);
    await tester.tap(find.text('无标签'));
    await tester.pump();
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('新建标签与已有标签同行，默认无标签使用中性色', (tester) async {
    var creates = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: TagChoiceField(
            tags: tags,
            selectedTagId: null,
            onChanged: (_) {},
            onCreateTag: () => creates++,
          ),
        ),
      ),
    ));

    final empty = tester.widget<FxChoiceChip>(
      find.widgetWithText(FxChoiceChip, '无标签'),
    );
    expect(empty.selected, isTrue);
    expect(
      empty.selectionColor,
      AppTheme.lightTheme().colorScheme.onSurfaceVariant,
    );
    expect(find.text('新建'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('#学习')).dy,
      closeTo(tester.getTopLeft(find.text('新建')).dy, 1),
    );
    await tester.tap(find.text('新建'));
    await tester.pump();
    expect(creates, 1);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('禁用时保留新建标签入口但不响应点击', (tester) async {
    var creates = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TagChoiceField(
          tags: tags,
          selectedTagId: null,
          enabled: false,
          onChanged: (_) {},
          onCreateTag: () => creates++,
        ),
      ),
    ));

    expect(find.text('新建'), findsOneWidget);
    await tester.tap(find.text('新建'));
    await tester.pump();
    expect(creates, 0);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android 360dp 大字号标签布局不会溢出', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFxTestHost(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 740),
          textScaler: TextScaler.linear(1.3),
        ),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: TagChoiceField(
              tags: tags,
              selectedTagId: 1,
              onChanged: (_) {},
              onCreateTag: () {},
            ),
          ),
        ),
      ),
    ));
    expect(find.text('#学习'), findsOneWidget);
    expect(find.text('#阅读'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('多选逐项增删并支持明确清空', (tester) async {
    Set<int> selected = {1};
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => TagChoiceField(
            tags: tags,
            selectedTagIds: selected,
            onMultipleChanged: (ids) => setState(() => selected = ids),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('#阅读'));
    await tester.pump();
    expect(selected, {1, 2});
    await tester.tap(find.text('#学习'));
    await tester.pump();
    expect(selected, {2});
    await tester.tap(find.text('无标签'));
    await tester.pump();
    expect(selected, isEmpty);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });


  testWidgets('多选禁用状态不会改变既有关联', (tester) async {
    var updates = 0;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: TagChoiceField(
          tags: tags,
          selectedTagIds: const {1},
          enabled: false,
          onMultipleChanged: (_) => updates++,
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('#阅读'));
    await tester.pump();
    await tester.tap(find.text('无标签'));
    await tester.pump();
    expect(updates, 0);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

}
