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

  // 桌面高密度语义基线。来源于既定高保真与 Fx 化前正式实现。
  static const double desktopCaptionSize = 12;
  static const double desktopSecondarySize = 13;
  static const double desktopFieldLabelSize = 12;
  static const double desktopControlSize = 13;
  static const double desktopChipSize = 12;
  static const double desktopCompactActionSize = 12;
  static const double desktopButtonSize = 13;
  static const double desktopBodySize = 14;
  static const double desktopCardTitleSize = 15;
  static const double desktopSectionTitleSize = 16;
  static const double desktopDialogTitleSize = 15;
  static const double desktopPageTitleSize = 16;
  static const double desktopEmphasizedInputSize = 14.5;

  /// 全屏休息等大号倒计时，独立于普通标题/统计展示。
  static const double timerDisplaySize = 48;

  /// Issue #9 的 Android 字体治理只作用于原生 Android。
  ///
  /// 平台判断集中在语义排版层；Fx 组件应读取这里解析后的语义样式，
  /// 不再自行判断 Windows / Android 后硬编码字号。
  static bool get useAndroidComponentTypography =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static double _height(double size, double lineHeight) => lineHeight / size;

  static TextStyle caption(BuildContext context) {
    final size =
        useAndroidComponentTypography ? captionSize : desktopCaptionSize;
    return Theme.of(context).textTheme.labelSmall!.copyWith(
          fontSize: size,
          height: _height(size, captionLineHeight),
        );
  }

  static TextStyle secondary(BuildContext context) {
    final size =
        useAndroidComponentTypography ? secondarySize : desktopSecondarySize;
    return Theme.of(context).textTheme.bodySmall!.copyWith(
          fontSize: size,
          height: _height(
            size,
            useAndroidComponentTypography ? secondaryLineHeight : 19.5,
          ),
        );
  }

  static TextStyle fieldLabel(BuildContext context) {
    final size =
        useAndroidComponentTypography ? fieldLabelSize : desktopFieldLabelSize;
    return Theme.of(context).textTheme.labelMedium!.copyWith(
          fontSize: size,
          height: _height(
            size,
            useAndroidComponentTypography ? fieldLabelLineHeight : 18,
          ),
          fontWeight: FontWeight.w600,
        );
  }

  static TextStyle control(BuildContext context) {
    final size =
        useAndroidComponentTypography ? controlSize : desktopControlSize;
    return Theme.of(context).textTheme.bodySmall!.copyWith(
          fontSize: size,
          height: _height(
            size,
            useAndroidComponentTypography ? controlLineHeight : 19.5,
          ),
        );
  }

  static TextStyle chip(BuildContext context) {
    final size = useAndroidComponentTypography ? chipSize : desktopChipSize;
    return Theme.of(context).textTheme.labelMedium!.copyWith(
          fontSize: size,
          height: _height(
            size,
            useAndroidComponentTypography ? chipLineHeight : 18,
          ),
          fontWeight: FontWeight.w500,
        );
  }

  static TextStyle compactAction(BuildContext context) => Theme.of(context)
      .textTheme
      .labelMedium!
      .copyWith(
        fontSize: useAndroidComponentTypography
            ? compactActionSize
            : desktopCompactActionSize,
        height: useAndroidComponentTypography
            ? _height(compactActionSize, compactActionLineHeight)
            : 1.5,
        fontWeight: FontWeight.w600,
      );

  /// 兼容旧调用的 Android 基线。新的 Fx 按钮应使用 [componentButton]。
  static TextStyle get button => TextStyle(
        fontSize: buttonSize,
        height: _height(buttonSize, buttonLineHeight),
        fontWeight: FontWeight.w600,
      );

  static TextStyle body(BuildContext context) {
    final size = useAndroidComponentTypography ? bodySize : desktopBodySize;
    return Theme.of(context).textTheme.bodyLarge!.copyWith(
          fontSize: size,
          height: _height(
            size,
            useAndroidComponentTypography ? bodyLineHeight : 21,
          ),
        );
  }

  static TextStyle cardTitle(BuildContext context) {
    final size =
        useAndroidComponentTypography ? cardTitleSize : desktopCardTitleSize;
    return Theme.of(context).textTheme.titleSmall!.copyWith(
          fontSize: size,
          height: _height(
            size,
            useAndroidComponentTypography ? cardTitleLineHeight : 21,
          ),
          fontWeight: FontWeight.w600,
        );
  }

  static TextStyle sectionTitle(BuildContext context) {
    final size = useAndroidComponentTypography
        ? sectionTitleSize
        : desktopSectionTitleSize;
    return Theme.of(context).textTheme.titleMedium!.copyWith(
          fontSize: size,
          height: _height(
            size,
            useAndroidComponentTypography ? sectionTitleLineHeight : 22,
          ),
          fontWeight: FontWeight.w600,
        );
  }

  /// Page Title 是页面级大标题语义；二级页面紧凑页头使用 [componentPageTitle]。
  static TextStyle pageTitle(BuildContext context) => Theme.of(context)
      .textTheme
      .titleLarge!
      .copyWith(
        fontSize: useAndroidComponentTypography
            ? pageTitleSize
            : desktopPageTitleSize,
        height: useAndroidComponentTypography
            ? _height(pageTitleSize, pageTitleLineHeight)
            : 1.4,
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

  /// 公共组件使用的平台解析语义。保留这些入口以表达组件意图，
  /// 具体字号与基础语义保持同源，避免页面和 Fx 组件形成两套平台判断。
  static TextStyle componentSecondary(BuildContext context) =>
      secondary(context);

  static TextStyle componentFieldLabel(BuildContext context) =>
      fieldLabel(context);

  static TextStyle componentControl(BuildContext context) => control(context);

  static TextStyle componentChip(BuildContext context) => chip(context);

  /// Slowlight 按钮语义：Windows 高保真为普通 13px / 紧凑 12px，
  /// Android 保持主要操作 15px / 紧凑操作 14px。FxButton 只消费该语义，
  /// 不再在组件内部重新判断平台。
  static TextStyle componentButton(
    BuildContext context, {
    bool compact = false,
  }) {
    if (compact) return compactAction(context);
    final size = useAndroidComponentTypography ? buttonSize : desktopButtonSize;
    return Theme.of(context).textTheme.labelLarge!.copyWith(
          fontSize: size,
          height: _height(
            size,
            useAndroidComponentTypography ? buttonLineHeight : 20,
          ),
          fontWeight: FontWeight.w600,
        );
  }

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
