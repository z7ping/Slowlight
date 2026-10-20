import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/ui/layout_tokens.dart';
import 'package:slowlight/ui/theme_manager.dart';

import '../support/fx_test_host.dart';

void main() {
  test('语义圆角区分 Sheet 与胶囊标签', () {
    expect(SlowlightRadius.sheet, 18);
    expect(SlowlightRadius.pill, greaterThan(100));
    expect(SlowlightRadius.lg, 12);
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final dark in [false, true]) {
      testWidgets('${platform.name} ${dark ? '暗色' : '亮色'} 视觉几何约束',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await tester.pumpWidget(buildFxTestHost(
          theme: dark ? ThemeManager.darkTheme : ThemeManager.lightTheme,
          shadTheme: dark ? ThemeManager.shadDark : ThemeManager.shadLight,
          home: Scaffold(
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FxChip(
                  label: '紧凑状态',
                  variant: FxChipVariant.secondary,
                  borderRadius: SlowlightRadius.pill,
                  padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                ),
                const FxChip(
                  label: '标准状态',
                  variant: FxChipVariant.secondary,
                  padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                ),
                const FxSegmented(
                  labels: ['今天', '回顾'],
                  selectedIndex: 0,
                  onChanged: _ignoreSelection,
                ),
                const FxCard(child: Text('标准卡片')),
                const FxCard(
                  padding: EdgeInsets.all(14),
                  child: Text('紧凑卡片'),
                ),
              ],
            ),
          ),
        ));
        await tester.pump();

        final chips = tester.widgetList<FxChip>(find.byType(FxChip)).toList();
        expect(chips, hasLength(2));
        expect(chips[0].padding, const EdgeInsets.symmetric(horizontal: 9, vertical: 3));
        expect(chips[0].borderRadius, SlowlightRadius.pill);
        expect(chips[1].padding, const EdgeInsets.symmetric(horizontal: 9, vertical: 4));
        final segment = find.byType(FxSegmented);
        final segmentHeight = tester.getSize(segment).height;
        final minimum = platform == TargetPlatform.android ? 48.0 : 36.0;
        expect(segmentHeight, greaterThanOrEqualTo(minimum));
        expect(tester.takeException(), isNull);
        await disposeFxTestHost(tester);
      });
    }
  }
}

void _ignoreSelection(int _) {}
