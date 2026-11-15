import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/models/calendar_record.dart';
import 'package:slowlight/ui/fx.dart';
import 'package:slowlight/widgets/calendar_month_grid.dart';

import '../support/fx_test_host.dart';

void main() {
  final tokens = jsonDecode(
    File('test/fixtures/design/ui_tokens.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  void expectTokens(String group, Map<String, Object?> actual) {
    for (final field in actual.entries) {
      final path = '$group.${field.key}';
      final expected = path.split('.').fold<dynamic>(
            tokens,
            (value, key) => (value as Map<String, dynamic>)[key],
          );
      expect(field.value, expected, reason: path);
    }
  }

  String rgb(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  test('UI-01 默认 Zinc 亮暗主题的页面、卡片和主文字', () {
    setActivePalette('zinc');
    expectTokens('colors', {
      'light.page': rgb(AppTheme.lightTheme().scaffoldBackgroundColor),
      'light.card':
          rgb(AppTheme.lightTheme().colorScheme.surfaceContainerLowest),
      'light.text': rgb(shadLightTheme().colorScheme.foreground),
      'dark.page': rgb(AppTheme.darkTheme().scaffoldBackgroundColor),
      'dark.card': rgb(AppTheme.darkTheme().colorScheme.surfaceContainerLowest),
      'dark.text': rgb(shadDarkTheme().colorScheme.foreground),
      'defaultAccent': rgb(getPalette('zinc').accent),
    });
  });

  test('UI-02/03/08 共享间距、圆角、断点和图标尺度', () {
    expectTokens('spacingDp', {
      'tight': SlowlightSpacing.xs,
      'group': SlowlightSpacing.md,
      'component': SlowlightSpacing.xl,
      'surface': SlowlightSpacing.xxxl,
      'section': SlowlightSpacing.page,
    });
    expectTokens('radiusDp', {
      'small': SlowlightRadius.sm,
      'control': SlowlightRadius.md,
      'card': SlowlightRadius.lg,
      'large': SlowlightRadius.xl,
    });
    expectTokens('breakpointsDp', {
      'medium': SlowlightBreakpoints.tabletMin,
      'desktop': SlowlightBreakpoints.desktopMin,
    });
    expectTokens('controls.visibleIconDp', {
      'small': SlowlightIconSize.sm,
      'medium': SlowlightIconSize.md,
      'large': SlowlightIconSize.lg,
    });
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('UI-04/${platform.name} 实际平台解析后的语义字号', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(buildFxTestHost(home: const Scaffold()));
      final context = tester.element(find.byType(Scaffold));
      expectTokens('typographyDp.${platform.name}', {
        'caption': SlowlightTypography.caption(context).fontSize,
        'secondary': SlowlightTypography.secondary(context).fontSize,
        'fieldLabel': SlowlightTypography.fieldLabel(context).fontSize,
        'control': SlowlightTypography.control(context).fontSize,
        'chip': SlowlightTypography.chip(context).fontSize,
        'compactAction': SlowlightTypography.compactAction(context).fontSize,
        'button': SlowlightTypography.componentButton(context).fontSize,
        'body': SlowlightTypography.body(context).fontSize,
        'cardTitle': SlowlightTypography.cardTitle(context).fontSize,
        'sectionTitle': SlowlightTypography.sectionTitle(context).fontSize,
        'pageTitle': SlowlightTypography.pageTitle(context).fontSize,
        if (platform == TargetPlatform.android)
          'hero': SlowlightTypography.hero(context).fontSize,
        if (platform == TargetPlatform.windows) ...{
          'dialogTitle':
              SlowlightTypography.componentDialogTitle(context).fontSize,
          'emphasizedInput':
              SlowlightTypography.emphasizedInput(context).fontSize,
        },
      });
      await disposeFxTestHost(tester);
    });
  }

  testWidgets('UI-05/07 Windows 按钮定义及 Android FxButton 实际命中面积', (tester) async {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final buttons = [
      for (final size in FxButtonSize.values)
        FxButton(label: size.name, size: size, onPressed: () {}),
    ];
    Future<void> pumpButtons(TargetPlatform platform) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(buildFxTestHost(
        home: Scaffold(body: Column(children: buttons)),
      ));
    }

    Finder button(FxButtonSize size) =>
        find.widgetWithText(FxButton, size.name);

    await pumpButtons(TargetPlatform.windows);
    expectTokens('controls', {
      'windowsButton.compactHeightDp': SlowlightControlSize.buttonSm,
      'windowsButton.defaultHeightDp': SlowlightControlSize.button,
      'windowsButton.largeHeightDp': SlowlightControlSize.buttonLg,
      'windowsButton.compactTextDp':
          tester.widget<Text>(find.text('sm')).style!.fontSize,
      'windowsButton.weight':
          tester.widget<Text>(find.text('md')).style!.fontWeight!.value,
      'windowsIconButtonDp': SlowlightPlatformDensity.iconButtonVisualSize,
      'windowsInput.horizontalInsetDp':
          SlowlightPlatformDensity.inputHorizontalPadding,
    });
    await disposeFxTestHost(tester);

    await pumpButtons(TargetPlatform.android);
    final minTouch = tokens['controls']['androidTouchMinDp'] as num;
    for (final buttonSize in FxButtonSize.values) {
      final size = tester.getSize(fxButtonHitTargetFinder(button(buttonSize)));
      expect(size.height, greaterThanOrEqualTo(minTouch));
      expect(size.width, greaterThanOrEqualTo(minTouch));
    }
    await disposeFxTestHost(tester);
  });

  testWidgets('UI-27 紧凑月格默认高度与横纵间距', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 850);
    addTearDown(tester.view.reset);
    final date = DateTime(2026, 11, 15);
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: CalendarMonthGrid(
          focusedMonth: date,
          selectedDate: date,
          records: const [],
          displayMode: CalendarDisplayMode.all,
          loading: false,
          onSelectDate: (_) {},
          onAddTask: (_) {},
          onOpenRecord: (_) {},
          onShowMore: (_) {},
        ),
      ),
    ));
    final grid = tester.widget<GridView>(find.byType(GridView));
    final geometry =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expectTokens('calendar', {
      'compactMonthCellHeightDp': geometry.mainAxisExtent,
      'monthCellGapDp': geometry.mainAxisSpacing,
    });
    expectTokens('calendar', {'monthCellGapDp': geometry.crossAxisSpacing});
    await disposeFxTestHost(tester);
  });
}
