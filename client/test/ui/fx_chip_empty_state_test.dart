import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('FxChip 在 360dp + 200% 字体缩放下保持可用', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: const Scaffold(
            body: Center(
              child: FxChip(
                label: '这是一个较长的状态标签',
                backgroundColor: Color(0xFFF4F4F5),
                foregroundColor: Color(0xFF52525B),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('这是一个较长的状态标签'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('FxChip 非 primary 变体不再退化为同一默认样式', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: const Scaffold(
          body: Column(
            children: [
              FxChip(label: '次要', variant: FxChipVariant.secondary),
              FxChip(label: '描边', variant: FxChipVariant.outline),
              FxChip(label: '危险', variant: FxChipVariant.destructive),
            ],
          ),
        ),
      ),
    );

    expect(find.text('次要'), findsOneWidget);
    expect(find.text('描边'), findsOneWidget);
    expect(find.text('危险'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('FxChoiceChip 在 Wrap 中保持内容宽度并横向排列', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FxChoiceChip(label: '工作', selected: true, onTap: () {}),
                FxChoiceChip(label: '生活', selected: false, onTap: () {}),
                FxChoiceChip(label: '学习', selected: false, onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    );

    final firstChip = find.byType(FxChoiceChip).first;
    expect(tester.getSize(firstChip).width, lessThan(160));

    final workTop = tester.getTopLeft(find.text('工作')).dy;
    final lifeTop = tester.getTopLeft(find.text('生活')).dy;
    final studyTop = tester.getTopLeft(find.text('学习')).dy;
    expect(lifeTop, closeTo(workTop, 0.5));
    expect(studyTop, closeTo(workTop, 0.5));
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Windows FxChoiceChip 保持桌面紧凑字号', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: FxChoiceChip(label: '工作', selected: true, onTap: () {}),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('工作')).style?.fontSize,
      SlowlightTypography.desktopChipSize,
    );
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('Android FxChoiceChip 使用 Android 可读字号', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: FxChoiceChip(label: '工作', selected: true, onTap: () {}),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.text('工作')).style?.fontSize,
      SlowlightTypography.chipSize,
    );
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });

  testWidgets('FxEmptyState 在 360dp + 200% 字体缩放下保持可读', (tester) async {
    await tester.pumpWidget(
      buildFxTestHost(
        theme: AppTheme.lightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: const Scaffold(
            body: FxEmptyState(
              emoji: '✨',
              title: '暂时没有内容',
              subtitle: '完成第一条记录后，这里会展示你的长期变化。',
            ),
          ),
        ),
      ),
    );

    expect(find.text('暂时没有内容'), findsOneWidget);
    expect(find.text('完成第一条记录后，这里会展示你的长期变化。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeFxTestHost(tester);
  });
}
