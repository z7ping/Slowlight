import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/theme_settings.dart';
import 'package:slowlight/ui/app_theme.dart';
import 'package:slowlight/ui/typography_tokens.dart';
import 'package:slowlight/utils/platform_font.dart';

void main() {
  test('Android 字号层级清晰且不提供缩小档', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(AppTheme.textXs, greaterThanOrEqualTo(12));
    expect(AppTheme.textSm, greaterThan(AppTheme.textXs));
    expect(AppTheme.textMd, greaterThan(AppTheme.textSm));
    expect(
      ThemeSettings.fontScaleOptions.keys.every((scale) => scale >= 1),
      isTrue,
    );
  });

  test('Android 跟随系统字体且不暴露桌面字体选项', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(PlatformFont.systemFontFamily, isNull);
    expect(ThemeSettings.fontFamilyOptions, {'': '跟随系统'});
    expect(ThemeSettings().resolvedFontFamily, isEmpty);
  });

  test('语义排版 Token 保持 Android 可读层级与约定行高', () {
    expect(SlowlightTypography.captionSize, 12);
    expect(SlowlightTypography.secondarySize, 14);
    expect(SlowlightTypography.buttonSize, 15);
    expect(SlowlightTypography.bodySize, 16);
    expect(SlowlightTypography.cardTitleSize, 16);
    expect(SlowlightTypography.pageTitleSize, 20);
    expect(SlowlightTypography.heroSize, 24);

    expect(SlowlightTypography.captionLineHeight, 16);
    expect(SlowlightTypography.secondaryLineHeight, 20);
    expect(SlowlightTypography.buttonLineHeight, 20);
    expect(SlowlightTypography.bodyLineHeight, 24);
    expect(SlowlightTypography.cardTitleLineHeight, 24);
    expect(SlowlightTypography.pageTitleLineHeight, 28);
    expect(SlowlightTypography.heroLineHeight, 32);
  });

  test('桌面高密度字号与 Android 基线分离', () {
    expect(SlowlightTypography.desktopSecondarySize, 13);
    expect(SlowlightTypography.desktopFieldLabelSize, 12);
    expect(SlowlightTypography.desktopControlSize, 13);
    expect(SlowlightTypography.desktopChipSize, 12);
    expect(SlowlightTypography.desktopBodySize, 14);
    expect(SlowlightTypography.desktopCardTitleSize, 15);
    expect(SlowlightTypography.desktopSectionTitleSize, 16);
    expect(SlowlightTypography.desktopPageTitleSize, 16);
  });

  testWidgets('Windows 语义样式不会继承 Android 放大字号', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    late TextStyle secondary;
    late TextStyle body;
    late TextStyle cardTitle;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            secondary = SlowlightTypography.secondary(context);
            body = SlowlightTypography.body(context);
            cardTitle = SlowlightTypography.cardTitle(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(secondary.fontSize, SlowlightTypography.desktopSecondarySize);
    expect(body.fontSize, SlowlightTypography.desktopBodySize);
    expect(cardTitle.fontSize, SlowlightTypography.desktopCardTitleSize);
  });

  testWidgets('Android 语义样式保持可读字号', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    late TextStyle secondary;
    late TextStyle body;
    late TextStyle cardTitle;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            secondary = SlowlightTypography.secondary(context);
            body = SlowlightTypography.body(context);
            cardTitle = SlowlightTypography.cardTitle(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(secondary.fontSize, SlowlightTypography.secondarySize);
    expect(body.fontSize, SlowlightTypography.bodySize);
    expect(cardTitle.fontSize, SlowlightTypography.cardTitleSize);
  });

  test('按钮排版不覆盖按钮变体提供的前景色', () {
    expect(SlowlightTypography.button.color, isNull);
    expect(SlowlightTypography.button.fontSize, 15);
    expect(SlowlightTypography.button.height, closeTo(20 / 15, 0.0001));
  });
}
