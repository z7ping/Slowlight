import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Slowlight 语义排版 Token。
///
/// 页面和业务组件应优先表达“这段文字是什么”，而不是自行选择字号。
/// Android 的阅读尺度治理与桌面端高密度视觉是两个平台目标：
/// - Android 按 Issue #9 使用更易读的语义字号；
/// - Windows / Web / 其他桌面端在 Fx 重构时保留既定高保真密度。
abstract final class SlowlightTypography {
  // Android / 通用阅读语义基线。
  static const double captionSize = 12;
  static const double captionLineHeight = 16;
  static const double secondarySize = 14;
  static const double secondaryLineHeight = 20;
  static const double fieldLabelSize = 14;
  static const double fieldLabelLineHeight = 20;
  static const double controlSize = 14;
  static const double controlLineHeight = 20;
  static const double chipSize = 14;
  static const double chipLineHeight = 20;
  static const double compactActionSize = 14;
  static const double compactActionLineHeight = 20;
  static const double buttonSize = 15;
  static const double buttonLineHeight = 20;
  static const double bodySize = 16;
  static const double bodyLineHeight = 24;
  static const double cardTitleSize = 16;
  static const double cardTitleLineHeight = 24;
  static const double sectionTitleSize = 18;
  static const double sectionTitleLineHeight = 24;
  static const double pageTitleSize = 20;
  static const double pageTitleLineHeight = 28;
  static const double heroSize = 24;
  static const double heroLineHeight = 32;
  static const double displaySize = 36;
  static const double displayLineHeight = 44;

  // 桌面高密度组件基线。来源于既定高保真与 Fx 化前正式实现。
  static const double desktopSecondarySize = 13;
  static const double desktopFieldLabelSize = 12;
  static const double desktopControlSize = 13;
  static const double desktopChipSize = 12;
  static const double desktopDialogTitleSize = 15;
  static const double desktopPageTitleSize = 16;
  static const double desktopEmphasizedInputSize = 14.5;

  /// 全屏休息等大号倒计时，独立于普通标题/统计展示。
  static const double timerDisplaySize = 48;

  /// Issue #9 的 Android 字体治理只作用于原生 Android。
  static bool get useAndroidComponentTypography =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static double _height(double size, double lineHeight) => lineHeight / size;

  static TextStyle caption(BuildContext context) => Theme.of(context)
      .textTheme
      .labelSmall!
      .copyWith(
        fontSize: captionSize,
        height: _height(captionSize, captionLineHeight),
      );

  static TextStyle secondary(BuildContext context) => Theme.of(context)
      .textTheme
      .bodySmall!
      .copyWith(
        fontSize: secondarySize,
        height: _height(secondarySize, secondaryLineHeight),
      );

  static TextStyle fieldLabel(BuildContext context) => Theme.of(context)
      .textTheme
      .labelMedium!
      .copyWith(
        fontSize: fieldLabelSize,
        height: _height(fieldLabelSize, fieldLabelLineHeight),
        fontWeight: FontWeight.w600,
      );

  static TextStyle control(BuildContext context) => Theme.of(context)
      .textTheme
      .bodySmall!
      .copyWith(
        fontSize: controlSize,
        height: _height(controlSize, controlLineHeight),
      );

  static TextStyle chip(BuildContext context) => Theme.of(context)
      .textTheme
      .labelMedium!
      .copyWith(
        fontSize: chipSize,
        height: _height(chipSize, chipLineHeight),
        fontWeight: FontWeight.w500,
      );

  static TextStyle compactAction(BuildContext context) => Theme.of(context)
      .textTheme
      .labelMedium!
      .copyWith(
        fontSize: compactActionSize,
        height: _height(compactActionSize, compactActionLineHeight),
        fontWeight: FontWeight.w600,
      );

  static TextStyle get button => TextStyle(
        fontSize: buttonSize,
        height: _height(buttonSize, buttonLineHeight),
        fontWeight: FontWeight.w600,
      );

  static TextStyle body(BuildContext context) => Theme.of(context)
      .textTheme
      .bodyLarge!
      .copyWith(
        fontSize: bodySize,
        height: _height(bodySize, bodyLineHeight),
      );

  static TextStyle cardTitle(BuildContext context) => Theme.of(context)
      .textTheme
      .titleSmall!
      .copyWith(
        fontSize: cardTitleSize,
        height: _height(cardTitleSize, cardTitleLineHeight),
        fontWeight: FontWeight.w600,
      );

  static TextStyle sectionTitle(BuildContext context) => Theme.of(context)
      .textTheme
      .titleMedium!
      .copyWith(
        fontSize: sectionTitleSize,
        height: _height(sectionTitleSize, sectionTitleLineHeight),
        fontWeight: FontWeight.w600,
      );

  static TextStyle pageTitle(BuildContext context) => Theme.of(context)
      .textTheme
      .titleLarge!
      .copyWith(
        fontSize: pageTitleSize,
        height: _height(pageTitleSize, pageTitleLineHeight),
        fontWeight: FontWeight.w600,
      );

  static TextStyle hero(BuildContext context) => Theme.of(context)
      .textTheme
      .headlineSmall!
      .copyWith(
        fontSize: heroSize,
        height: _height(heroSize, heroLineHeight),
        fontWeight: FontWeight.w600,
      );

  static TextStyle display(BuildContext context) => Theme.of(context)
      .textTheme
      .displaySmall!
      .copyWith(
        fontSize: displaySize,
        height: _height(displaySize, displayLineHeight),
        fontWeight: FontWeight.w700,
      );

  /// 公共组件使用的平台解析语义。
  static TextStyle componentSecondary(BuildContext context) =>
      useAndroidComponentTypography
          ? secondary(context)
          : Theme.of(context).textTheme.bodySmall!.copyWith(
                fontSize: desktopSecondarySize,
              );

  static TextStyle componentFieldLabel(BuildContext context) =>
      useAndroidComponentTypography
          ? fieldLabel(context)
          : Theme.of(context).textTheme.labelSmall!.copyWith(
                fontSize: desktopFieldLabelSize,
                fontWeight: FontWeight.w600,
              );

  static TextStyle componentControl(BuildContext context) =>
      useAndroidComponentTypography
          ? control(context)
          : Theme.of(context).textTheme.bodySmall!.copyWith(
                fontSize: desktopControlSize,
              );

  static TextStyle componentChip(BuildContext context) =>
      useAndroidComponentTypography
          ? chip(context)
          : Theme.of(context).textTheme.labelSmall!.copyWith(
                fontSize: desktopChipSize,
                fontWeight: FontWeight.w500,
              );

  static TextStyle componentDialogTitle(BuildContext context) =>
      useAndroidComponentTypography
          ? cardTitle(context).copyWith(fontWeight: FontWeight.w700)
          : Theme.of(context).textTheme.titleSmall!.copyWith(
                fontSize: desktopDialogTitleSize,
                fontWeight: FontWeight.w700,
              );

  static TextStyle componentPageTitle(BuildContext context) =>
      useAndroidComponentTypography
          ? pageTitle(context).copyWith(fontWeight: FontWeight.w700)
          : Theme.of(context).textTheme.titleSmall!.copyWith(
                fontSize: desktopPageTitleSize,
                fontWeight: FontWeight.w700,
              );

  static TextStyle emphasizedInput(BuildContext context) =>
      useAndroidComponentTypography
          ? body(context).copyWith(fontWeight: FontWeight.w600)
          : Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontSize: desktopEmphasizedInputSize,
                fontWeight: FontWeight.w600,
              );
}
